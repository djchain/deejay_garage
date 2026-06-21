import Foundation
import Network

// MARK: - Connection State

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int)
}

// MARK: - ConnectionManager

final class ConnectionManager: ObservableObject {

    // MARK: Published Properties

    @Published private(set) var state: ConnectionState = .disconnected
    @Published var outputBuffer: String = ""

    /// The most recent tmux session list received from the bridge.
    @Published var tmuxSessions: [TmuxSessionInfo] = []

    // MARK: Callbacks

    /// Called whenever the terminal receives output text from the bridge.
    var onOutput: ((String) -> Void)?

    /// Called when the connection state changes.
    var onStateChange: ((ConnectionState) -> Void)?

    /// Called when the bridge detects a tmux detach (prefix+d).
    var onSessionDetached: ((String) -> Void)?

    // MARK: Private Properties

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var pingTimer: Timer?
    private var reconnectTimer: Timer?
    private var reconnectAttempts: Int = 0
    var shouldReconnect: Bool = false
    private var targetURL: URL?

    private let maxReconnectDelay: TimeInterval = 30.0
    private let pingInterval: TimeInterval = 30.0
    private let maxReconnectAttempts: Int = 5

    private let pathMonitor = NWPathMonitor()
    private let pathMonitorQueue = DispatchQueue(label: "com.clauderemote.pathmonitor")

    /// Incremented on each `connect()` call. Used to discard stale receive callbacks.
    private var connectionGeneration: Int = 0

    // MARK: Initialization

    init() {
        startPathMonitor()
    }

    deinit {
        disconnect()
        pathMonitor.cancel()
        pingTimer?.invalidate()
        reconnectTimer?.invalidate()
    }

    // MARK: - Public API

    /// Connects to the bridge at the given WebSocket URL.
    /// - Parameter url: A `ws://` or `wss://` URL.
    /// - Parameter enableReconnect: If false, a failed connection won't auto-retry.
    func connect(to url: URL, enableReconnect: Bool = true) {
        print("[ConnectionManager] Connecting to: \(url.absoluteString), reconnect: \(enableReconnect)")

        // Clean up previous connection state WITHOUT calling the full
        // disconnect() path (which invalidates URLSession asynchronously,
        // creating a race that kills the new connection on high-latency links).
        stopReconnectTimer()
        stopPingTimer()
        webSocketTask?.cancel()
        webSocketTask = nil
        // Let the old URLSession finish its cancellation on a background queue
        // so it doesn't race with the new one we're about to create.
        let oldSession = urlSession
        urlSession = nil
        DispatchQueue.global(qos: .utility).async {
            oldSession?.invalidateAndCancel()
        }

        shouldReconnect = enableReconnect
        reconnectAttempts = 0
        targetURL = url
        connectionGeneration += 1
        let myGeneration = connectionGeneration

        updateState(.connecting)

        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.networkServiceType = .responsiveData
        let session = URLSession(configuration: config)
        urlSession = session
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()

        listenForMessages(generation: myGeneration)
        startPingTimer()
    }

    /// Disconnects from the bridge and stops reconnection attempts.
    func disconnect() {
        shouldReconnect = false
        stopReconnectTimer()
        stopPingTimer()
        reconnectAttempts = 0
        targetURL = nil

        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil

        tmuxSessions = []
        updateState(.disconnected)
    }

    /// Sends an arbitrary text message over the WebSocket.
    func send(_ message: String) {
        guard (state == .connected || state == .connecting), let task = webSocketTask else {
            print("[ConnectionManager] Cannot send — not connected")
            return
        }

        let wsMessage = URLSessionWebSocketTask.Message.string(message)
        task.send(wsMessage) { [weak self] error in
            if let error = error {
                print("[ConnectionManager] Send error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self?.handleDisconnect()
                }
            }
        }
    }

    /// Sends a signal message (e.g., Ctrl-C / SIGINT).
    func sendSignal(_ name: String) {
        let msg = SignalMessage(name: name)
        if let json = msg.toJSON() {
            send(json)
        }
    }

    /// Sends a terminal resize notification.
    func sendResize(cols: Int, rows: Int) {
        let msg = ResizeMessage(cols: cols, rows: rows)
        if let json = msg.toJSON() {
            send(json)
        }
    }

    /// Sends a ping (heartbeat) message.
    func sendPing() {
        let msg = PingMessage()
        if let json = msg.toJSON() {
            send(json)
        }
    }

    // MARK: - Session Management

    /// Requests the list of tmux sessions from the bridge.
    func sendListSessions() {
        if let json = BridgeMessage.listSessions.toJSON() {
            send(json)
        }
    }

    /// Switches to the specified tmux session.
    func sendSwitchSession(_ name: String) {
        let msg = SwitchSessionMessage(sessionName: name)
        if let json = BridgeMessage.switchSession(msg).toJSON() {
            send(json)
        }
    }

    /// Creates a new window in the specified tmux session.
    func sendNewWindow(_ sessionName: String) {
        let msg = NewWindowMessage(sessionName: sessionName)
        if let json = BridgeMessage.newWindow(msg).toJSON() {
            send(json)
        }
    }

    /// Selects a window in the current tmux session by direction ("next" or "prev").
    func sendSelectWindow(_ direction: String) {
        let msg = SelectWindowMessage(direction: direction)
        if let json = BridgeMessage.selectWindow(msg).toJSON() {
            send(json)
        }
    }

    /// Kills a tmux session by name.
    func sendKillSession(_ name: String) {
        let msg = KillSessionMessage(sessionName: name)
        if let json = BridgeMessage.killSession(msg).toJSON() {
            send(json)
        }
    }

    // MARK: - Private: WebSocket Receive Loop

    private func listenForMessages(generation: Int) {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            // Discard callbacks from a previous connection
            guard self.connectionGeneration == generation else {
                print("[ConnectionManager] Discarding stale receive callback (gen \(generation), current \(self.connectionGeneration))")
                return
            }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleIncomingMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleIncomingMessage(text)
                    }
                @unknown default:
                    break
                }
                // Continue listening
                self.listenForMessages(generation: generation)

            case .failure(let error):
                let nsError = error as NSError
                print("[ConnectionManager] Receive error: \(nsError.localizedDescription) (domain: \(nsError.domain), code: \(nsError.code))")
                // Check generation again before triggering disconnect
                guard self.connectionGeneration == generation else { return }
                DispatchQueue.main.async {
                    self.handleDisconnect()
                }
            }
        }
    }

    private func handleIncomingMessage(_ text: String) {
        guard let message = BridgeMessage.fromJSON(text) else {
            print("[ConnectionManager] Unrecognized message: \(text.prefix(100))")
            return
        }

        switch message {
        case .output(let msg):
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.outputBuffer = msg.data
                self.onOutput?(msg.data)
                // First output message confirms the connection is alive
                if self.state != .connected {
                    self.updateState(.connected)
                }
            }
        case .pong:
            // Pong received — heartbeat is healthy; transition to connected if still connecting
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if self.state != .connected {
                    self.updateState(.connected)
                }
            }
        case .sessionListResponse(let msg):
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.tmuxSessions = msg.sessions
                print("[ConnectionManager] Received \(msg.sessions.count) tmux session(s)")
            }
        case .sessionDetached(let msg):
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                print("[ConnectionManager] Session detached: \(msg.session)")
                self.onSessionDetached?(msg.session)
            }
        case .sessionKilled(let msg):
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                print("[ConnectionManager] Session killed: \(msg.session)")
                // Auto-refresh session list after a kill.
                self.sendListSessions()
            }
        case .sessionCreated, .sessionSwitched:
            // Auto-refresh session list when a session is created or switched.
            // This eliminates the need for a hard-coded delay on the client side.
            DispatchQueue.main.async { [weak self] in
                self?.sendListSessions()
            }
        default:
            print("[ConnectionManager] Ignored message type: \(message)")
        }
    }

    // MARK: - Private: State Management

    private func updateState(_ newState: ConnectionState) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.state != newState {
                self.state = newState
                self.onStateChange?(newState)
            }
        }
    }

    private func handleDisconnect() {
        print("[ConnectionManager] handleDisconnect — state: \(state), shouldReconnect: \(shouldReconnect), targetURL: \(targetURL?.absoluteString ?? "nil")")
        // Only trigger reconnect if we were previously connected or connecting
        switch state {
        case .connected, .connecting:
            webSocketTask?.cancel()
            webSocketTask = nil
            stopPingTimer()
            scheduleReconnect()
        case .reconnecting, .disconnected:
            break
        }
    }

    // MARK: - Private: Reconnection

    private func scheduleReconnect() {
        guard shouldReconnect else {
            updateState(.disconnected)
            return
        }

        guard reconnectAttempts < maxReconnectAttempts else {
            print("[ConnectionManager] Max reconnect attempts (\(maxReconnectAttempts)) reached — giving up")
            shouldReconnect = false
            targetURL = nil
            updateState(.disconnected)
            return
        }

        reconnectAttempts += 1
        let delay = calculateReconnectDelay(attempt: reconnectAttempts)

        updateState(.reconnecting(attempt: reconnectAttempts))
        print("[ConnectionManager] Reconnecting in \(delay)s (attempt \(reconnectAttempts))")

        stopReconnectTimer()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self, let url = self.targetURL else { return }
            self.connect(to: url)
        }
    }

    private func calculateReconnectDelay(attempt: Int) -> TimeInterval {
        // Exponential backoff: 1s, 2s, 4s, 8s, 16s, 30s cap
        let delay = pow(2.0, Double(attempt - 1))
        return min(delay, maxReconnectDelay)
    }

    private func stopReconnectTimer() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }

    // MARK: - Private: Heartbeat (Ping)

    private func startPingTimer() {
        stopPingTimer()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.pingTimer = Timer.scheduledTimer(withTimeInterval: self.pingInterval, repeats: true) { [weak self] _ in
                self?.sendPing()
            }
        }
    }

    private func stopPingTimer() {
        pingTimer?.invalidate()
        pingTimer = nil
    }

    // MARK: - Private: Network Path Monitoring

    private func startPathMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            if path.status == .satisfied {
                // Network became available — attempt reconnect if needed
                if case .disconnected = self.state, self.shouldReconnect, self.targetURL != nil {
                    print("[ConnectionManager] Network available — reconnecting")
                    DispatchQueue.main.async {
                        self.scheduleReconnect()
                    }
                }
            }
        }
        pathMonitor.start(queue: pathMonitorQueue)
    }
}

// MARK: - BridgeMessage Extension for JSON Convenience

private extension InputMessage {
    func toJSON() -> String? {
        BridgeMessage.input(self).toJSON()
    }
}

private extension SignalMessage {
    func toJSON() -> String? {
        BridgeMessage.signal(self).toJSON()
    }
}

private extension ResizeMessage {
    func toJSON() -> String? {
        BridgeMessage.resize(self).toJSON()
    }
}

private extension PingMessage {
    func toJSON() -> String? {
        BridgeMessage.ping.toJSON()
    }
}
