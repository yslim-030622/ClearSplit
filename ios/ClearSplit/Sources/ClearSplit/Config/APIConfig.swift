import Foundation

enum APIConfig {
    private static let localHosts: Set<String> = ["localhost", "127.0.0.1", "::1"]

    static var baseURL: URL {
        // Prefer Info.plist key "API_BASE_URL" if present
        if let urlString = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
           let url = URL(string: urlString) {
            return url
        }

        // Default for simulator/local dev (use IPv4 to avoid IPv6 connection issues)
        return URL(string: "http://127.0.0.1:8000")!
    }

    static var isLoopbackHost: Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return localHosts.contains(host)
    }

    static var requiresLANBaseURLForCurrentRuntime: Bool {
        isLoopbackHost && !isRunningOnSimulator
    }

    static var deviceLoopbackHintMessage: String {
        "Cannot connect to server. If using a real device, set API_BASE_URL to your Mac LAN IP (e.g. http://192.168.x.x:8000)."
    }

    private static var isRunningOnSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    /// Helper for devices: pass a LAN URL like http://192.168.1.10:8000 via Info.plist or scheme-specific xcconfig.
}
