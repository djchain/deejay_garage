import Foundation
import Darwin

// MARK: - DiscoveredService

struct DiscoveredService: Identifiable, Equatable {
    let id: UUID
    let name: String
    let host: String
    let port: Int

    init(id: UUID = UUID(), name: String, host: String, port: Int) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
    }
}

// MARK: - BonjourDiscovery

final class BonjourDiscovery: NSObject, ObservableObject {

    // MARK: Published Properties

    @Published var discoveredServices: [DiscoveredService] = []

    // MARK: Private Properties

    private var browser: NetServiceBrowser?
    private var services: [NetService] = []
    private var resolvingServices: [NetService] = []
    private let serviceType = "_claudebridge._tcp"
    private let serviceDomain = "local."

    // MARK: Public API

    /// Starts browsing for `_claudebridge._tcp` services on the local network.
    func startBrowsing() {
        guard browser == nil else {
            print("[BonjourDiscovery] Already browsing")
            return
        }

        discoveredServices.removeAll()
        services.removeAll()
        resolvingServices.removeAll()

        let newBrowser = NetServiceBrowser()
        newBrowser.delegate = self
        newBrowser.searchForServices(ofType: serviceType, inDomain: serviceDomain)
        browser = newBrowser

        print("[BonjourDiscovery] Started browsing for \(serviceType)")
    }

    /// Stops browsing for services.
    func stopBrowsing() {
        browser?.stop()
        browser = nil
        print("[BonjourDiscovery] Stopped browsing")
    }

    /// Whether the browser is currently running.
    var isBrowsing: Bool {
        browser != nil
    }
}

// MARK: - NetServiceBrowserDelegate

extension BonjourDiscovery: NetServiceBrowserDelegate {

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        print("[BonjourDiscovery] Found service: \(service.name) type=\(service.type) domain=\(service.domain)")
        services.append(service)
        resolveService(service)

        if !moreComing {
            print("[BonjourDiscovery] Batch complete — resolving \(services.count) service(s)")
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        print("[BonjourDiscovery] Service removed: \(service.name)")
        services.removeAll { $0 == service }
        discoveredServices.removeAll { $0.name == service.name }
    }

    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        print("[BonjourDiscovery] Search stopped")
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        print("[BonjourDiscovery] Search failed: \(errorDict)")
    }
}

// MARK: - NetServiceDelegate (Resolution)

extension BonjourDiscovery: NetServiceDelegate {

    private func resolveService(_ service: NetService) {
        service.delegate = self
        resolvingServices.append(service)
        // Set a 10-second timeout for resolution
        service.resolve(withTimeout: 10.0)
        print("[BonjourDiscovery] Resolving service: \(service.name)")
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        print("[BonjourDiscovery] Resolved service: \(sender.name)")

        resolvingServices.removeAll { $0 == sender }

        guard let host = Self.preferredHost(addresses: sender.addresses ?? [], fallbackHostName: sender.hostName) else {
            print("[BonjourDiscovery] No usable host for service: \(sender.name)")
            return
        }

        let port = sender.port
        let discovered = DiscoveredService(
            name: sender.name,
            host: host,
            port: Int(port)
        )

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if !self.discoveredServices.contains(discovered) {
                self.discoveredServices.append(discovered)
                print("[BonjourDiscovery] Added discovered service: \(discovered.name) @ \(discovered.host):\(discovered.port)")
            }
        }
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        print("[BonjourDiscovery] Failed to resolve service: \(sender.name), error: \(errorDict)")
        resolvingServices.removeAll { $0 == sender }
    }

    static func preferredHost(addresses: [Data], fallbackHostName: String?) -> String? {
        for address in addresses {
            guard let host = ipv4Host(from: address), !isLoopbackIPv4(host) else {
                continue
            }
            return host
        }

        guard let fallbackHostName else {
            return nil
        }

        let trimmed = fallbackHostName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        return trimmed.hasSuffix(".") ? String(trimmed.dropLast()) : trimmed
    }

    private static func ipv4Host(from address: Data) -> String? {
        address.withUnsafeBytes { rawBuffer -> String? in
            guard let baseAddress = rawBuffer.baseAddress,
                  rawBuffer.count >= MemoryLayout<sockaddr>.size else {
                return nil
            }

            let socketAddress = baseAddress.assumingMemoryBound(to: sockaddr.self)
            guard Int32(socketAddress.pointee.sa_family) == AF_INET,
                  rawBuffer.count >= MemoryLayout<sockaddr_in>.size else {
                return nil
            }

            let ipv4Address = baseAddress.assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr
            var output = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            var mutableAddress = ipv4Address

            guard inet_ntop(AF_INET, &mutableAddress, &output, socklen_t(INET_ADDRSTRLEN)) != nil else {
                return nil
            }

            return String(cString: output)
        }
    }

    private static func isLoopbackIPv4(_ host: String) -> Bool {
        host.hasPrefix("127.") || host == "0.0.0.0"
    }
}
