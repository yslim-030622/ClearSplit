//
//  KeychainService.swift
//  ClearSplit
//

import Foundation
import Security

enum KeychainService {
    private static let tokensKey = "com.clearsplit.authTokens"

    // MARK: - Save
    
    static func saveTokens(_ tokens: AuthTokens) throws {
        // Encode the entire AuthTokens object as JSON
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(tokens) else {
            throw NSError(domain: "KeychainService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode tokens"])
        }

        // Remove existing value
        deleteTokens()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tokensKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: "KeychainService", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Failed to save tokens to Keychain"])
        }
    }

    // MARK: - Retrieve

    static func getTokens() -> AuthTokens? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tokensKey,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        
        // Decode the AuthTokens object from JSON
        let decoder = JSONDecoder()
        return try? decoder.decode(AuthTokens.self, from: data)
    }

    // MARK: - Delete

    static func deleteTokens() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tokensKey
        ]
        SecItemDelete(query as CFDictionary)
    }
}
