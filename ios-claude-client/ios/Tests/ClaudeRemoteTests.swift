import XCTest
import Darwin
@testable import ClaudeRemote

// MARK: - Message Tests (M1-M6)

final class MessageTests: XCTestCase {

    // M1: InputMessage encoding
    func testInputMessageEncoding() throws {
        let msg = InputMessage(data: "ls\n")
        let bridgeMsg = BridgeMessage.input(msg)
        let json = bridgeMsg.toJSON()

        XCTAssertNotNil(json, "JSON should not be nil")

        let data = json!.data(using: .utf8)!
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(dict?["type"] as? String, "input")
        XCTAssertEqual(dict?["data"] as? String, "ls\n")
    }

    // M2: OutputMessage decoding
    func testOutputMessageDecoding() throws {
        let json = """
        {"type":"output","data":"hello"}
        """
        let msg = BridgeMessage.fromJSON(json)

        guard case .output(let output)? = msg else {
            XCTFail("Expected .output message")
            return
        }
        XCTAssertEqual(output.data, "hello")
    }

    // M3: SignalMessage encoding
    func testSignalMessageEncoding() throws {
        let msg = SignalMessage(name: "int")
        let bridgeMsg = BridgeMessage.signal(msg)
        let json = bridgeMsg.toJSON()

        XCTAssertNotNil(json)

        let data = json!.data(using: .utf8)!
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(dict?["type"] as? String, "signal")
        XCTAssertEqual(dict?["name"] as? String, "int")
    }

    // M4: ResizeMessage encoding
    func testResizeMessageEncoding() throws {
        let msg = ResizeMessage(cols: 80, rows: 24)
        let bridgeMsg = BridgeMessage.resize(msg)
        let json = bridgeMsg.toJSON()

        XCTAssertNotNil(json)

        let data = json!.data(using: .utf8)!
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(dict?["type"] as? String, "resize")
        XCTAssertEqual(dict?["cols"] as? Int, 80)
        XCTAssertEqual(dict?["rows"] as? Int, 24)
    }

    // M5: PingMessage encoding/decoding
    func testPingMessageRoundTrip() throws {
        // Encoding
        let pingMsg = PingMessage()
        let bridgeMsg = BridgeMessage.ping
        let json = bridgeMsg.toJSON()

        XCTAssertNotNil(json)

        let data = json!.data(using: .utf8)!
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(dict?["type"] as? String, "ping")

        // Decoding
        let decoded = BridgeMessage.fromJSON(json!)
        if case .ping = decoded {
            // Success
        } else {
            XCTFail("Expected .ping message")
        }
    }

    // M6: Invalid JSON decoding
    func testInvalidJSONDecoding() throws {
        // Unknown type
        let unknownJson = """
        {"type":"unknown","data":"something"}
        """
        let msg = BridgeMessage.fromJSON(unknownJson)
        XCTAssertNil(msg, "Unknown message type should return nil")

        // Malformed JSON
        let malformedJson = "this is not json"
        let malformedMsg = BridgeMessage.fromJSON(malformedJson)
        XCTAssertNil(malformedMsg, "Malformed JSON should return nil")

        // Missing type field
        let missingTypeJson = """
        {"data":"hello"}
        """
        let missingTypeMsg = BridgeMessage.fromJSON(missingTypeJson)
        XCTAssertNil(missingTypeMsg, "Missing type field should return nil")
    }
}

// MARK: - SessionInfo Tests (S1-S3)

final class SessionInfoTests: XCTestCase {

    // S1: SessionInfo serialization
    func testSessionInfoEncodingDecoding() throws {
        let session = SessionInfo(
            name: "Test Server",
            host: "192.168.1.100",
            port: 9090
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(session)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SessionInfo.self, from: data)

        XCTAssertEqual(decoded.id, session.id)
        XCTAssertEqual(decoded.name, "Test Server")
        XCTAssertEqual(decoded.host, "192.168.1.100")
        XCTAssertEqual(decoded.port, 9090)
    }

    // S2: URL construction
    func testSessionURL() throws {
        let session = SessionInfo(
            name: "Local",
            host: "localhost",
            port: 9090
        )

        XCTAssertEqual(session.urlString, "ws://localhost:9090/ws")
        XCTAssertEqual(session.url?.absoluteString, "ws://localhost:9090/ws")
    }

    func testSessionEquality() throws {
        let id = UUID()
        let now = Date()
        let session1 = SessionInfo(id: id, name: "A", host: "host1", port: 9090, lastUsed: now)
        let session2 = SessionInfo(id: id, name: "A", host: "host1", port: 9090, lastUsed: now)
        XCTAssertEqual(session1, session2)
    }
}

// MARK: - SessionStore Tests (S1-S3)

final class SessionStoreTests: XCTestCase {

    var store: SessionStore!

    override func setUp() {
        super.setUp()
        store = SessionStore()
        // Clear existing sessions for test isolation
        for session in store.sessions {
            store.remove(session.id)
        }
    }

    // S1: Save connection info
    func testAddSession() throws {
        XCTAssertEqual(store.sessions.count, 0)

        let session = SessionInfo(name: "Test", host: "192.168.1.1", port: 9090)
        store.add(session)

        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.sessions.first?.name, "Test")
    }

    // S2: List sorted by most recent
    func testSessionsSortedByLastUsed() throws {
        let session1 = SessionInfo(name: "A", host: "10.0.0.1", port: 9090, lastUsed: Date().addingTimeInterval(-100))
        let session2 = SessionInfo(name: "B", host: "10.0.0.2", port: 9090, lastUsed: Date().addingTimeInterval(-50))

        store.add(session1)
        store.add(session2)

        // The most recently used should come first
        XCTAssertEqual(store.sessions.first?.name, "B")
        XCTAssertEqual(store.sessions.last?.name, "A")
    }

    // S3: Delete session
    func testRemoveSession() throws {
        let session = SessionInfo(name: "Test", host: "192.168.1.1", port: 9090)
        store.add(session)
        XCTAssertEqual(store.sessions.count, 1)

        store.remove(session.id)
        XCTAssertEqual(store.sessions.count, 0)
    }

    // Duplicate detection: same host+port should update, not duplicate
    func testAddDuplicateHostPort() throws {
        let session1 = SessionInfo(name: "First", host: "10.0.0.1", port: 9090)
        store.add(session1)
        XCTAssertEqual(store.sessions.count, 1)

        let session2 = SessionInfo(name: "Second", host: "10.0.0.1", port: 9090)
        store.add(session2)
        XCTAssertEqual(store.sessions.count, 1, "Should not create duplicate entries for same host:port")
        XCTAssertEqual(store.sessions.first?.name, "Second", "Should update the name to the latest")
    }

    func testUpdateSession() throws {
        let session = SessionInfo(name: "Old", host: "10.0.0.1", port: 9090)
        store.add(session)

        var updated = session
        updated.name = "Updated"
        store.update(updated)

        XCTAssertEqual(store.sessions.first?.name, "Updated")
    }
}

// MARK: - ConnectionManager State Tests

final class ConnectionManagerStateTests: XCTestCase {

    var manager: ConnectionManager!

    override func setUp() {
        super.setUp()
        manager = ConnectionManager()
    }

    override func tearDown() {
        manager.disconnect()
        manager = nil
        super.tearDown()
    }

    func testInitialState() throws {
        XCTAssertEqual(manager.state, .disconnected)
    }

    func testDisconnectFromInitial() throws {
        // Disconnecting from initial state should keep it disconnected
        manager.disconnect()
        XCTAssertEqual(manager.state, .disconnected)
    }

    // Test that connecting to an invalid URL doesn't crash
    func testInvalidURLConnect() throws {
        guard let url = URL(string: "ws://192.0.2.1:9999/ws") else {
            XCTFail("Failed to create URL")
            return
        }
        // This should not crash; connection should fail gracefully
        let expectation = XCTestExpectation(description: "State becomes connecting")
        manager.onStateChange = { state in
            if state == .connecting {
                expectation.fulfill()
            }
        }
        manager.connect(to: url)
        // Wait for the async state update
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(manager.state, .connecting)
    }
}

// MARK: - BonjourDiscovery Tests

final class BonjourDiscoveryTests: XCTestCase {

    var discovery: BonjourDiscovery!

    override func setUp() {
        super.setUp()
        discovery = BonjourDiscovery()
    }

    override func tearDown() {
        discovery.stopBrowsing()
        discovery = nil
        super.tearDown()
    }

    func testInitialState() throws {
        XCTAssertTrue(discovery.discoveredServices.isEmpty)
        XCTAssertFalse(discovery.isBrowsing)
    }

    func testStartBrowsing() throws {
        discovery.startBrowsing()
        // After starting, isBrowsing should be true
        XCTAssertTrue(discovery.isBrowsing)
    }

    func testStopBrowsing() throws {
        discovery.startBrowsing()
        XCTAssertTrue(discovery.isBrowsing)

        discovery.stopBrowsing()
        XCTAssertFalse(discovery.isBrowsing)
    }

    func testMultipleStartStop() throws {
        // Starting and stopping multiple times should not crash
        discovery.startBrowsing()
        discovery.startBrowsing() // should be no-op
        discovery.stopBrowsing()
        discovery.stopBrowsing() // should be no-op
        discovery.startBrowsing()
        XCTAssertTrue(discovery.isBrowsing)
        discovery.stopBrowsing()
    }

    func testPreferredHostSkipsLoopbackIPv4() throws {
        let host = BonjourDiscovery.preferredHost(
            addresses: [
                makeIPv4AddressData("127.0.0.1"),
                makeIPv4AddressData("192.168.3.91"),
            ],
            fallbackHostName: "Deejays-Mac-mini.local."
        )

        XCTAssertEqual(host, "192.168.3.91")
    }

    func testPreferredHostTrimsFallbackRootDot() throws {
        let host = BonjourDiscovery.preferredHost(
            addresses: [],
            fallbackHostName: "Deejays-Mac-mini.local."
        )

        XCTAssertEqual(host, "Deejays-Mac-mini.local")
    }

    private func makeIPv4AddressData(_ ip: String) -> Data {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        inet_pton(AF_INET, ip, &address.sin_addr)

        return Data(bytes: &address, count: MemoryLayout<sockaddr_in>.size)
    }
}
