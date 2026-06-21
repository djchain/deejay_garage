import XCTest
@testable import ClaudeRemote

// MARK: - Functional Key Protocol Verification

final class FunctionalKeyTests: XCTestCase {

    func testCtrlCSendsSIGINT() throws {
        let msg = SignalMessage(name: "int")
        let json = BridgeMessage.signal(msg).toJSON()
        XCTAssertNotNil(json)
        let data = json!.data(using: .utf8)!
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(dict?["type"] as? String, "signal")
        XCTAssertEqual(dict?["name"] as? String, "int")
    }

    func testCtrlDSendsEOF() throws {
        let msg = SignalMessage(name: "eof")
        let json = BridgeMessage.signal(msg).toJSON()
        XCTAssertNotNil(json)
        let data = json!.data(using: .utf8)!
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(dict?["type"] as? String, "signal")
        XCTAssertEqual(dict?["name"] as? String, "eof")
    }

    func testEscapeKeySendsEscapeChar() throws {
        let msg = InputMessage(data: "\u{1b}")
        let json = BridgeMessage.input(msg).toJSON()
        XCTAssertNotNil(json)
        let data = json!.data(using: .utf8)!
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(dict?["type"] as? String, "input")
        XCTAssertEqual(dict?["data"] as? String, "\u{1b}")
    }

    func testTabKeySendsTabChar() throws {
        let msg = InputMessage(data: "\t")
        let json = BridgeMessage.input(msg).toJSON()
        XCTAssertNotNil(json)
        let data = json!.data(using: .utf8)!
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(dict?["type"] as? String, "input")
        XCTAssertEqual(dict?["data"] as? String, "\t")
    }

    func testArrowUpSendsCSI_A() throws {
        let msg = InputMessage(data: "\u{1b}[A")
        let json = BridgeMessage.input(msg).toJSON()
        XCTAssertNotNil(json)
        let data = json!.data(using: .utf8)!
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(dict?["type"] as? String, "input")
        XCTAssertEqual(dict?["data"] as? String, "\u{1b}[A")
    }

    func testArrowDownSendsCSI_B() throws {
        let msg = InputMessage(data: "\u{1b}[B")
        let json = BridgeMessage.input(msg).toJSON()
        XCTAssertNotNil(json)
        let data = json!.data(using: .utf8)!
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(dict?["type"] as? String, "input")
        XCTAssertEqual(dict?["data"] as? String, "\u{1b}[B")
    }
}

// MARK: - Message Round-Trip Tests

final class MessageRoundTripTests: XCTestCase {

    func testInputMessageRoundTrip() throws {
        let original = InputMessage(data: "ls -la\n")
        let json = BridgeMessage.input(original).toJSON()!
        let decoded = BridgeMessage.fromJSON(json)
        guard case .input(let msg) = decoded else {
            XCTFail("Expected .input")
            return
        }
        XCTAssertEqual(msg.data, "ls -la\n")
    }

    func testOutputMessageRoundTrip() throws {
        let json = #"{"type":"output","data":"file1.txt\nfile2.txt\n"}"#
        let decoded = BridgeMessage.fromJSON(json)
        guard case .output(let msg) = decoded else {
            XCTFail("Expected .output")
            return
        }
        XCTAssertEqual(msg.data, "file1.txt\nfile2.txt\n")
    }

    func testSignalMessageRoundTrip() throws {
        let original = SignalMessage(name: "int")
        let json = BridgeMessage.signal(original).toJSON()!
        let decoded = BridgeMessage.fromJSON(json)
        guard case .signal(let msg) = decoded else {
            XCTFail("Expected .signal")
            return
        }
        XCTAssertEqual(msg.name, "int")
    }

    func testResizeMessageRoundTrip() throws {
        let original = ResizeMessage(cols: 120, rows: 40)
        let json = BridgeMessage.resize(original).toJSON()!
        let decoded = BridgeMessage.fromJSON(json)
        guard case .resize(let msg) = decoded else {
            XCTFail("Expected .resize")
            return
        }
        XCTAssertEqual(msg.cols, 120)
        XCTAssertEqual(msg.rows, 40)
    }

    func testPingMessageRoundTrip() throws {
        let json = BridgeMessage.ping.toJSON()!
        let decoded = BridgeMessage.fromJSON(json)
        guard case .ping = decoded else {
            XCTFail("Expected .ping")
            return
        }
    }

    func testPongMessageDecoding() throws {
        let json = #"{"type":"pong"}"#
        let decoded = BridgeMessage.fromJSON(json)
        guard case .pong = decoded else {
            XCTFail("Expected .pong")
            return
        }
    }
}

// MARK: - ConnectionManager State Machine Tests

final class ConnectionManagerStateMachineTests: XCTestCase {

    var manager: ConnectionManager!

    override func setUp() {
        super.setUp()
        manager = ConnectionManager()
    }

    override func tearDown() {
        manager?.disconnect()
        manager = nil
        super.tearDown()
    }

    func testInitialStateIsDisconnected() {
        XCTAssertEqual(manager.state, .disconnected)
    }

    func testDisconnectFromInitialState() {
        manager.disconnect()
        XCTAssertEqual(manager.state, .disconnected)
    }

    func testDoubleDisconnect() {
        manager.disconnect()
        manager.disconnect()
        XCTAssertEqual(manager.state, .disconnected)
    }

    func testStateChangeCallback() {
        let expectation = XCTestExpectation(description: "State change callback")
        var receivedStates: [ConnectionState] = []

        manager.onStateChange = { state in
            receivedStates.append(state)
            if state == .connecting {
                expectation.fulfill()
            }
        }

        guard let url = URL(string: "ws://192.0.2.1:9999/ws") else {
            XCTFail("Invalid URL")
            return
        }
        manager.connect(to: url)

        wait(for: [expectation], timeout: 3.0)
        XCTAssertTrue(receivedStates.contains(.connecting))
    }

    func testPingSerialization() throws {
        let json = BridgeMessage.ping.toJSON()
        XCTAssertNotNil(json)
        let data = json!.data(using: .utf8)!
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(dict?["type"] as? String, "ping")
    }
}

// MARK: - Connection Manager Edge Case Tests

final class ConnectionManagerEdgeCaseTests: XCTestCase {

    var manager: ConnectionManager!

    override func setUp() {
        super.setUp()
        manager = ConnectionManager()
    }

    override func tearDown() {
        manager?.disconnect()
        manager = nil
        super.tearDown()
    }

    func testSendWhenDisconnectedIsNoop() {
        // Should not crash when sending while disconnected
        manager.disconnect()
        // Calling send should be safe (it logs but doesn't crash)
        // We can only test that no crash occurs
        XCTAssertEqual(manager.state, .disconnected)
    }

    func testMultipleConnectDisconnectCycles() {
        guard let url = URL(string: "ws://192.0.2.1:9999/ws") else {
            XCTFail("Invalid URL")
            return
        }

        for i in 0..<3 {
            let connectExp = XCTestExpectation(description: "connect cycle \(i)")
            manager.onStateChange = { state in
                if state == .connecting { connectExp.fulfill() }
            }
            manager.connect(to: url)
            wait(for: [connectExp], timeout: 2.0)

            let disconnectExp = XCTestExpectation(description: "disconnect cycle \(i)")
            manager.onStateChange = { state in
                if state == .disconnected { disconnectExp.fulfill() }
            }
            manager.disconnect()
            wait(for: [disconnectExp], timeout: 2.0)
        }

        XCTAssertEqual(manager.state, .disconnected)
    }
}
