import Foundation

// MARK: - Message Types

enum MessageType: String, Codable {
    case input
    case output
    case signal
    case ping
    case pong
    case resize
    case listSessions = "list_sessions"
    case switchSession = "switch_session"
    case newWindow = "new_window"
    case selectWindow = "select_window"
    case killSession = "kill_session"
    case sessionListResponse = "session_list"
    case sessionCreated = "session_created"
    case sessionSwitched = "session_switched"
    case sessionDetached = "session_detached"
    case sessionKilled = "session_killed"
}

// MARK: - Individual Message Types

struct InputMessage: Codable {
    let type: String
    let data: String

    init(data: String) {
        self.type = MessageType.input.rawValue
        self.data = data
    }
}

struct OutputMessage: Codable {
    let type: String
    let data: String

    init(data: String) {
        self.type = MessageType.output.rawValue
        self.data = data
    }
}

struct SignalMessage: Codable {
    let type: String
    let name: String

    init(name: String) {
        self.type = MessageType.signal.rawValue
        self.name = name
    }
}

struct ResizeMessage: Codable {
    let type: String
    let cols: Int
    let rows: Int

    init(cols: Int, rows: Int) {
        self.type = MessageType.resize.rawValue
        self.cols = cols
        self.rows = rows
    }
}

struct PingMessage: Codable {
    let type: String

    init() {
        self.type = MessageType.ping.rawValue
    }
}

struct PongMessage: Codable {
    let type: String

    init() {
        self.type = MessageType.pong.rawValue
    }
}

// MARK: - Session Management Messages

struct ListSessionsMessage: Codable {
    let type: String

    init() {
        self.type = MessageType.listSessions.rawValue
    }
}

struct SwitchSessionMessage: Codable {
    let type: String
    let sessionName: String

    init(sessionName: String) {
        self.type = MessageType.switchSession.rawValue
        self.sessionName = sessionName
    }
}

struct NewWindowMessage: Codable {
    let type: String
    let sessionName: String

    init(sessionName: String) {
        self.type = MessageType.newWindow.rawValue
        self.sessionName = sessionName
    }
}

struct SelectWindowMessage: Codable {
    let type: String
    let direction: String

    init(direction: String) {
        self.type = MessageType.selectWindow.rawValue
        self.direction = direction
    }
}

struct KillSessionMessage: Codable {
    let type: String
    let sessionName: String

    init(sessionName: String) {
        self.type = MessageType.killSession.rawValue
        self.sessionName = sessionName
    }
}

// MARK: - Session List Response

/// Represents a tmux session as returned by the bridge.
struct TmuxSessionInfo: Codable, Identifiable, Equatable {
    let name: String
    let windows: Int

    var id: String { name }
}

struct SessionListResponseMessage: Codable {
    let type: String
    let sessions: [TmuxSessionInfo]
}

// MARK: - Session Detached Response

struct SessionDetachedMessage: Codable {
    let type: String
    let session: String
}

// MARK: - Session Killed Response

struct SessionKilledMessage: Codable {
    let type: String
    let session: String
}

// MARK: - BridgeMessage (Unified Enum)

enum BridgeMessage {
    case input(InputMessage)
    case output(OutputMessage)
    case signal(SignalMessage)
    case resize(ResizeMessage)
    case ping
    case pong
    case listSessions
    case switchSession(SwitchSessionMessage)
    case newWindow(NewWindowMessage)
    case selectWindow(SelectWindowMessage)
    case killSession(KillSessionMessage)
    case sessionListResponse(SessionListResponseMessage)
    case sessionCreated
    case sessionSwitched
    case sessionDetached(SessionDetachedMessage)
    case sessionKilled(SessionKilledMessage)

    // MARK: Encoding

    /// Encodes the message to a JSON string suitable for sending over WebSocket.
    func toJSON() -> String? {
        let encoder = JSONEncoder()
        do {
            switch self {
            case .input(let msg):
                let data = try encoder.encode(msg)
                return String(data: data, encoding: .utf8)
            case .output(let msg):
                let data = try encoder.encode(msg)
                return String(data: data, encoding: .utf8)
            case .signal(let msg):
                let data = try encoder.encode(msg)
                return String(data: data, encoding: .utf8)
            case .resize(let msg):
                let data = try encoder.encode(msg)
                return String(data: data, encoding: .utf8)
            case .ping:
                let msg = PingMessage()
                let data = try encoder.encode(msg)
                return String(data: data, encoding: .utf8)
            case .pong:
                let msg = PongMessage()
                let data = try encoder.encode(msg)
                return String(data: data, encoding: .utf8)
            case .listSessions:
                let msg = ListSessionsMessage()
                let data = try encoder.encode(msg)
                return String(data: data, encoding: .utf8)
            case .switchSession(let msg):
                let data = try encoder.encode(msg)
                return String(data: data, encoding: .utf8)
            case .newWindow(let msg):
                let data = try encoder.encode(msg)
                return String(data: data, encoding: .utf8)
            case .selectWindow(let msg):
                let data = try encoder.encode(msg)
                return String(data: data, encoding: .utf8)
            case .killSession(let msg):
                let data = try encoder.encode(msg)
                return String(data: data, encoding: .utf8)
            case .sessionListResponse(let msg):
                let data = try encoder.encode(msg)
                return String(data: data, encoding: .utf8)
            case .sessionCreated, .sessionSwitched, .sessionDetached, .sessionKilled:
                return nil // server→client only, never encoded on iOS side
            }
        } catch {
            print("[BridgeMessage] Encoding error: \(error)")
            return nil
        }
    }

    // MARK: Decoding

    /// Decodes a JSON string (received from WebSocket) into a `BridgeMessage`.
    /// Returns `nil` if the JSON is invalid or the type is unknown.
    static func fromJSON(_ jsonString: String) -> BridgeMessage? {
        guard let jsonData = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let typeString = dict["type"] as? String,
              let messageType = MessageType(rawValue: typeString) else {
            return nil
        }

        let decoder = JSONDecoder()
        switch messageType {
        case .output:
            if let msg = try? decoder.decode(OutputMessage.self, from: jsonData) {
                return .output(msg)
            }
        case .input:
            if let msg = try? decoder.decode(InputMessage.self, from: jsonData) {
                return .input(msg)
            }
        case .signal:
            if let msg = try? decoder.decode(SignalMessage.self, from: jsonData) {
                return .signal(msg)
            }
        case .resize:
            if let msg = try? decoder.decode(ResizeMessage.self, from: jsonData) {
                return .resize(msg)
            }
        case .ping:
            return .ping
        case .pong:
            return .pong
        case .listSessions:
            return .listSessions
        case .switchSession:
            if let msg = try? decoder.decode(SwitchSessionMessage.self, from: jsonData) {
                return .switchSession(msg)
            }
        case .newWindow:
            if let msg = try? decoder.decode(NewWindowMessage.self, from: jsonData) {
                return .newWindow(msg)
            }
        case .selectWindow:
            if let msg = try? decoder.decode(SelectWindowMessage.self, from: jsonData) {
                return .selectWindow(msg)
            }
        case .killSession:
            if let msg = try? decoder.decode(KillSessionMessage.self, from: jsonData) {
                return .killSession(msg)
            }
        case .sessionCreated:
            return .sessionCreated
        case .sessionSwitched:
            return .sessionSwitched
        case .sessionDetached:
            if let msg = try? decoder.decode(SessionDetachedMessage.self, from: jsonData) {
                return .sessionDetached(msg)
            }
        case .sessionKilled:
            if let msg = try? decoder.decode(SessionKilledMessage.self, from: jsonData) {
                return .sessionKilled(msg)
            }
        case .sessionListResponse:
            if let msg = try? decoder.decode(SessionListResponseMessage.self, from: jsonData) {
                return .sessionListResponse(msg)
            }
        }
        return nil
    }
}

// MARK: - Codable Conformances for Top-Level Messaging

/// A generic inbound message wrapper used when the type is determined at decode-time.
struct InboundMessage: Codable {
    let type: String
    let data: String?
    let name: String?
    let cols: Int?
    let rows: Int?
}
