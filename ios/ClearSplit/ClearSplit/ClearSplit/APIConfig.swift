//
//  APIConfig.swift
//  ClearSplit
//
//  API configuration loaded from build settings (xcconfig)
//

import Foundation

enum APIConfig {
    static var baseURL: URL {
        // Read from Info.plist which gets it from xcconfig via build settings
        if let urlString = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
           !urlString.isEmpty,
           let url = URL(string: urlString) {
            #if DEBUG
            print("📡 API Base URL: \(urlString)")
            #endif
            return url
        }
        
        // Fallback for safety (should never happen if xcconfig is set up correctly)
        #if DEBUG
        print("⚠️ API_BASE_URL not found in Info.plist, using localhost fallback")
        #endif
        return URL(string: "http://localhost:8000")!
    }
}
