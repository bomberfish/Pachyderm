//
//  Keychain.swift
//  Pachyderm
//

import Foundation
import Security

/// A small interface to the keychain for the OAuth token.
///
/// The earlier code kept the token in `UserDefaults`. Each process in the app
/// container can read such a value. The system also puts the value into a backup
/// without encryption.
nonisolated enum Keychain {
    private static let service = Bundle.main.bundleIdentifier ?? "ca.bomberfish.Pachyderm"

    static func string(for account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func set(_ value: String?, for account: String) -> Bool {
        guard let value, !value.isEmpty else { return remove(account) }

        let data = Data(value.utf8)
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        switch SecItemUpdate(query as CFDictionary, attributes as CFDictionary) {
        case errSecSuccess:
            return true
        case errSecItemNotFound:
            return SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil) == errSecSuccess
        default:
            return false
        }
    }

    @discardableResult
    static func remove(_ account: String) -> Bool {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
