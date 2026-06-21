import Foundation
import Network

// MARK: - NetworkUtils

/// Helper utilities for detecting network configuration (Tailscale IP, etc.)
struct NetworkUtils {

    /// Detects the Tailscale IP address (100.x.x.x) on local network interfaces.
    /// Returns `nil` if Tailscale is not detected on any interface.
    static func detectTailscaleIP() -> String? {
        return detectIP { $0.hasPrefix("100.") }
    }

    /// Detects the WiFi/LAN IP address (192.168.x.x or 10.x.x.x).
    /// Returns `nil` if no local IP is detected.
    static func detectLocalIP() -> String? {
        return detectIP {
            $0.hasPrefix("192.168.") || $0.hasPrefix("10.") || $0.hasPrefix("172.")
        }
    }

    /// Scans all network interfaces for an IPv4 address matching the given filter.
    private static func detectIP(matching filter: (String) -> Bool) -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return nil
        }
        defer { freeifaddrs(ifaddr) }

        var cursor = firstAddr
        while true {
            let addr = cursor.pointee
            if addr.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let sa = UnsafeMutablePointer<sockaddr>(mutating: addr.ifa_addr)
                if getnameinfo(sa, socklen_t(addr.ifa_addr.pointee.sa_len),
                               &hostname, socklen_t(hostname.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    let address = String(cString: hostname)
                    if filter(address) {
                        return address
                    }
                }
            }
            guard let next = addr.ifa_next else { break }
            cursor = next
        }
        return nil
    }

    /// Represents a known Mac configuration for connection.
    struct MacConfig: Codable {
        let hostname: String
        var localIP: String?
        var tailscaleIP: String?
        var port: Int

        init(hostname: String, localIP: String? = nil, tailscaleIP: String? = nil, port: Int = 9090) {
            self.hostname = hostname
            self.localIP = localIP
            self.tailscaleIP = tailscaleIP
            self.port = port
        }

        /// Returns the best available URL for connecting.
        /// Prefers local IP first (faster), falls back to Tailscale.
        func bestURL() -> URL? {
            if let local = localIP {
                return URL(string: "ws://\(local):\(port)/ws")
            }
            if let tailscale = tailscaleIP {
                return URL(string: "ws://\(tailscale):\(port)/ws")
            }
            return nil
        }
    }

    // MARK: - Persistence

    private static let macConfigKey = "claude_remote_mac_config"

    /// Saves the primary Mac configuration to UserDefaults.
    static func saveMacConfig(_ config: MacConfig) {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: macConfigKey)
        }
    }

    /// Loads the primary Mac configuration from UserDefaults.
    static func loadMacConfig() -> MacConfig? {
        guard let data = UserDefaults.standard.data(forKey: macConfigKey) else {
            return nil
        }
        return try? JSONDecoder().decode(MacConfig.self, from: data)
    }

    /// Clears the stored Mac configuration.
    static func clearMacConfig() {
        UserDefaults.standard.removeObject(forKey: macConfigKey)
    }
}
