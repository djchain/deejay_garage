import Foundation
import SwiftUI
import Combine

// MARK: - TerminalViewModel

final class TerminalViewModel: ObservableObject {

    // MARK: Sub-Managers

    @Published var connectionManager: ConnectionManager
    @Published var bonjourDiscovery: BonjourDiscovery
    @Published var sessionStore: SessionStore

    // MARK: Navigation State

    @Published var selectedSession: String? = nil

    // MARK: UI State

    @Published var isConnecting: Bool = false
    @Published var showBonjourPicker: Bool = false
    @Published var connectHost: String = ""
    @Published var connectPort: String = "9090"
    @Published var fontSize: Double = 14.0
    @Published var terminalTheme: TerminalTheme = .system
    @Published var hapticFeedbackEnabled: Bool = true
    @Published var showInputHint: Bool = true

    /// Set by TerminalTabView before detaching so SessionListView can distinguish
    /// intentional detach from accidental connection loss in its onChange handler.
    @Published var detachRequested: Bool = false

    /// Convenient access to session store sessions array.
    var sessions: [SessionInfo] { sessionStore.sessions }

    // MARK: Terminal Feed

    /// A closure for the SwiftTerm view to call when user input is received from the terminal.
    var onTerminalInput: ((String) -> Void)?

    /// A closure used by the SwiftTerm view to retrieve user-entered text.
    var onTerminalByteInput: (([UInt8]) -> Void)?

    // MARK: Combine Subscriptions

    private var cancellables = Set<AnyCancellable>()

    // MARK: Initialization

    init(
        connectionManager: ConnectionManager = ConnectionManager(),
        bonjourDiscovery: BonjourDiscovery = BonjourDiscovery(),
        sessionStore: SessionStore = SessionStore()
    ) {
        self.connectionManager = connectionManager
        self.bonjourDiscovery = bonjourDiscovery
        self.sessionStore = sessionStore

        // Forward ConnectionManager's internal state changes to SwiftUI.
        // Without this, @Published on connectionManager only fires when the
        // reference itself is replaced — not when connectionManager.state changes.
        connectionManager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    // MARK: - Connection Management

    /// Connects to a service discovered via Bonjour.
    func connectToDiscovered(_ service: DiscoveredService) {
        let session = SessionInfo(
            name: service.name,
            host: service.host,
            port: service.port
        )
        sessionStore.add(session)
        // Save LAN IP from mDNS. We don't know the Mac's Tailscale IP
        // from mDNS discovery — only user-supplied manual input can provide it.
        let config = NetworkUtils.MacConfig(
            hostname: service.name,
            localIP: service.host,
            tailscaleIP: nil,
            port: service.port
        )
        NetworkUtils.saveMacConfig(config)
        connect(to: service.host, port: service.port, name: service.name)
    }

    /// Connects to a manually specified host and port.
    func connectManually(host: String, port: Int, name: String? = nil) {
        let sessionName = name ?? "\(host):\(port)"
        let session = SessionInfo(name: sessionName, host: host, port: port)
        sessionStore.add(session)
        // If the user typed a Tailscale IP (100.x.x.x), save it as tailscaleIP.
        // Otherwise treat it as a LAN IP. NEVER call detectTailscaleIP() here —
        // that returns the iPhone's own Tailscale IP, not the Mac's.
        let isTailscaleIP = host.hasPrefix("100.") && host.split(separator: ".").count == 4
        let config = NetworkUtils.MacConfig(
            hostname: sessionName,
            localIP: isTailscaleIP ? nil : host,
            tailscaleIP: isTailscaleIP ? host : nil,
            port: port
        )
        NetworkUtils.saveMacConfig(config)
        connect(to: host, port: port, name: sessionName)
    }

    /// Reconnects to a previously used session.
    func connectToSession(_ session: SessionInfo) {
        guard let url = session.url else { return }
        sessionStore.touch(session.id)
        connectionManager.connect(to: url)
    }

    /// Internal connect helper.
    private func connect(to host: String, port: Int, name: String) {
        guard let url = URL(string: "ws://\(host):\(port)/ws") else {
            print("[TerminalViewModel] Invalid URL: \(host):\(port)")
            return
        }
        // Save session for history and future auto-connect
        let session = SessionInfo(name: name, host: host, port: port)
        sessionStore.add(session)
        connectionManager.connect(to: url)
    }

    /// Disconnects from the current session.
    func disconnect() {
        connectionManager.disconnect()
    }

    // MARK: - Input Forwarding

    /// Forwards keyboard input to the WebSocket connection.
    func sendInput(_ text: String) {
        let msg = BridgeMessage.input(InputMessage(data: text))
        if let json = msg.toJSON() {
            connectionManager.send(json)
        }
    }

    /// Sends a signal (e.g., Ctrl-C for SIGINT).
    func sendSignal(_ name: String) {
        connectionManager.sendSignal(name)
    }

    /// Sends a resize notification.
    func sendResize(cols: Int, rows: Int) {
        connectionManager.sendResize(cols: cols, rows: rows)
    }

    // MARK: - Bonjour

    /// Set to true once auto-connect has been attempted to avoid re-triggering.
    private var autoConnectAttempted = false

    func startDiscovery() {
        bonjourDiscovery.startBrowsing()
        attemptAutoConnect()
    }

    func stopDiscovery() {
        bonjourDiscovery.stopBrowsing()
    }

    // MARK: - Auto-Connect

    /// Attempts to auto-connect using the following priority:
    /// 1. mDNS-discovered service (WiFi auto-discovery)
    /// 2. Stored Mac config's local IP (from a previous manual connection)
    /// 3. Tailscale IP (100.x.x.x, covered by NSAllowsArbitraryLoads)
    ///
    /// NOTE: We do NOT use `NetworkUtils.detectLocalIP()` because it returns the
    /// device's own IP, not the Mac's IP — which would cause a self-connection loop.
    private func attemptAutoConnect() {
        guard !autoConnectAttempted, case .disconnected = connectionManager.state else {
            return
        }
        autoConnectAttempted = true

        // Priority 1: Check if mDNS already discovered a service
        if let service = bonjourDiscovery.discoveredServices.first {
            connectToDiscovered(service)
            return
        }

        // Load stored config (may have both localIP + tailscaleIP from a previous manual connect)
        let savedConfig = NetworkUtils.loadMacConfig()

        // Priority 2: Try saved Mac config's local IP (WiFi LAN connection)
        // Auto-connect with reconnect disabled — if this one attempt fails,
        // let the user manually connect via the ConnectView instead of looping.
        if let localIP = savedConfig?.localIP {
            let port = savedConfig?.port ?? 9090
            if let url = URL(string: "ws://\(localIP):\(port)/ws") {
                connectionManager.connect(to: url, enableReconnect: false)
                return
            }
        }

        // Priority 3: Try saved Mac config's tailscaleIP (set during manual Tailscale connect)
        if let tailscaleIP = savedConfig?.tailscaleIP {
            let port = savedConfig?.port ?? 9090
            if let url = URL(string: "ws://\(tailscaleIP):\(port)/ws") {
                connectionManager.connect(to: url, enableReconnect: false)
                return
            }
        }

        // Nothing auto-connectable found — user will see manual connect sheet
        print("[TerminalViewModel] No auto-connect target found")
    }

    /// Called when a Bonjour service is discovered — triggers auto-connect if not already connected.
    func onServiceDiscovered(_ service: DiscoveredService) {
        guard case .disconnected = connectionManager.state else { return }
        // Auto-connect to the first discovered service
        connectToDiscovered(service)
    }

    // MARK: - Session Management

    /// Requests the list of tmux sessions from the bridge.
    func listSessions() {
        connectionManager.sendListSessions()
    }

    /// Switches to the specified tmux session.
    func switchSession(name: String) {
        connectionManager.sendSwitchSession(name)
        selectedSession = name
    }

    /// Creates a new window in the specified tmux session.
    func newWindow(session: String) {
        connectionManager.sendNewWindow(session)
    }

    /// Selects a window by direction ("next" or "prev").
    func selectWindow(direction: String) {
        connectionManager.sendSelectWindow(direction)
    }

    /// Kills a tmux session by name.
    func killSession(name: String) {
        connectionManager.sendKillSession(name)
    }

    // MARK: - Terminal Cleanup / Scrollback

    func clearTerminal() {
        // The SwiftTerm view handles this internally via its own API.
        // This method is a convenience hook.
    }
}

// MARK: - Terminal Theme

enum TerminalTheme: String, CaseIterable, Codable {
    case system
    case light
    case dark

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}
