import Foundation

/// Represents a saved connection session.
struct SessionInfo: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var host: String
    var port: Int
    var lastUsed: Date

    init(id: UUID = UUID(), name: String, host: String, port: Int, lastUsed: Date = Date()) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.lastUsed = lastUsed
    }

    /// A display-friendly URL string.
    var urlString: String {
        "ws://\(host):\(port)/ws"
    }

    /// Construct a URL from the stored host and port.
    var url: URL? {
        var components = URLComponents()
        components.scheme = "ws"
        components.host = host
        components.port = port
        components.path = "/ws"
        return components.url
    }
}
