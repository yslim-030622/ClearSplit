import Foundation

enum APIConfig {
    static var baseURL: URL {
        // Prefer Info.plist key "API_BASE_URL" if present
        if let urlString = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
           let url = URL(string: urlString) {
            return url
        }

        // Default for simulator/local dev (use IPv4 to avoid IPv6 connection issues)
        return URL(string: "http://127.0.0.1:8000")!
    }

    /// Helper for devices: pass a LAN URL like http://192.168.1.10:8000 via Info.plist or scheme-specific xcconfig.
}
