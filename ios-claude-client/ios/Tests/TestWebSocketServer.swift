import Foundation
import Network
import XCTest

/// A lightweight WebSocket echo server for integration tests.
///
/// Uses `NWListener` with `NWProtocolWebSocket` to automatically handle
/// the WebSocket HTTP upgrade handshake. Incoming WebSocket text messages
/// are delivered to `onMessage`; the server can also send messages back
/// via `send(_:on:)`.
///
/// Usage:
/// ```
/// let server = try TestWebSocketServer()
/// try server.start()
/// // ConnectionManager connects to ws://127.0.0.1:\(server.port)/ws
/// server.onMessage = { text, conn in
///     // echo back, or verify contents
/// }
/// // ...
/// server.stop()
/// ```
final class TestWebSocketServer {
    let port: UInt16
    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.clauderemote.tests.websocket", qos: .default)
    private(set) var connections: [NWConnection] = []
    private(set) var receivedMessages: [String] = []
    private var isRunning = false

    /// Called when a WebSocket text message is received.
    /// Parameters: (message text, the connection it arrived on)
    var onMessage: ((String, NWConnection) -> Void)?

    /// Called when a new connection completes the WebSocket handshake.
    var onConnected: ((NWConnection) -> Void)?

    /// Called when a connection is lost.
    var onDisconnected: ((NWConnection) -> Void)?

    // MARK: - Initialization

    /// Creates a new WebSocket server on the given port.
    /// - Parameter port: 0 = any available port (read `port` property after `start()`).
    init(port: UInt16 = 0) throws {
        let params = NWParameters(tls: nil)
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        guard let wsPort = NWEndpoint.Port(rawValue: port) else {
            throw TestWebSocketServer.Error.invalidPort(port)
        }

        self.listener = try NWListener(using: params, on: wsPort)
        self.port = port
        setupListener()
    }

    enum Error: Swift.Error {
        case invalidPort(UInt16)
        case startFailed(Swift.Error)
    }

    // MARK: - Lifecycle

    /// Starts listening on the configured port.
    /// The server begins accepting WebSocket connections.
    func start() throws {
        let startExpectation = XCTestExpectation(description: "server started")
        var startError: Swift.Error?

        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let s = self {
                    s.isRunning = true
                    if s.port == 0 {
                        // The real port is the listener's assigned port
                        // We can't modify let, but we access via listener.port
                    }
                }
                startExpectation.fulfill()
            case .failed(let error):
                startError = error
                startExpectation.fulfill()
            default:
                break
            }
        }

        listener.start(queue: queue)

        // Wait for listener to be ready (up to 5 seconds)
        let result = XCTWaiter.wait(for: [startExpectation], timeout: 5.0)
        if result != .completed {
            throw Error.startFailed(startError ?? TestWebSocketServer.Error.invalidPort(port))
        }
    }

    /// Returns the actual port the server is listening on.
    /// Useful when `port` was initialized to 0 (any available port).
    var actualPort: UInt16 {
        return listener.port?.rawValue ?? port
    }

    /// Stops the server and cleans up all connections.
    func stop() {
        for conn in connections {
            conn.cancel()
        }
        connections.removeAll()
        receivedMessages.removeAll()
        listener.cancel()
        isRunning = false
    }

    /// Sends a WebSocket text message on the given connection.
    func send(_ text: String, on connection: NWConnection) {
        guard let data = text.data(using: .utf8) else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "text", metadata: [metadata])
        connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { _ in })
    }

    /// Sends a WebSocket text message to all connected clients.
    func broadcast(_ text: String) {
        for conn in connections {
            send(text, on: conn)
        }
    }

    /// Clears the received messages buffer.
    func clearReceivedMessages() {
        receivedMessages.removeAll()
    }

    // MARK: - Private

    private func setupListener() {
        listener.newConnectionHandler = { [weak self] connection in
            guard let self = self else { return }

            connection.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .ready:
                    self.connections.append(connection)
                    self.onConnected?(connection)
                    self.receiveNextMessage(on: connection)
                case .failed(let error):
                    print("[TestServer] Connection failed: \(error)")
                    self.removeConnection(connection)
                    self.onDisconnected?(connection)
                case .cancelled:
                    self.removeConnection(connection)
                    self.onDisconnected?(connection)
                default:
                    break
                }
            }

            connection.start(queue: self.queue)
        }
    }

    private func receiveNextMessage(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, context, isComplete, error in
            guard let self = self else { return }

            if let error = error {
                print("[TestServer] Receive error: \(error)")
                self.removeConnection(connection)
                self.onDisconnected?(connection)
                return
            }

            if let data = data, let text = String(data: data, encoding: .utf8) {
                self.receivedMessages.append(text)
                self.onMessage?(text, connection)
            }

            if isComplete {
                self.removeConnection(connection)
                self.onDisconnected?(connection)
            } else {
                // Continue listening for more messages
                self.receiveNextMessage(on: connection)
            }
        }
    }

    private func removeConnection(_ connection: NWConnection) {
        connections.removeAll { $0 === connection }
    }
}

// MARK: - XCTestCase Helper

extension XCTestCase {
    /// Creates a started `TestWebSocketServer` on a random port and
    /// automatically stops it during `tearDown`.
    ///
    /// Returns the server and the WebSocket URL to connect to.
    func startTestServer(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> (server: TestWebSocketServer, url: URL) {
        let server = try TestWebSocketServer(port: 0)
        try server.start()
        let port = server.actualPort
        guard let url = URL(string: "ws://127.0.0.1:\(port)/ws") else {
            server.stop()
            XCTFail("Failed to construct WebSocket URL", file: file, line: line)
            throw TestWebSocketServer.Error.invalidPort(UInt16(port))
        }
        return (server, url)
    }
}
