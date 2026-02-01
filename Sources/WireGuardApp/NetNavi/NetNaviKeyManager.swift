//
// NetNavi – WireGuard local key manager

import Foundation
import Security

enum NetNaviKeyManager {

    // MARK: - Keychain keys

    private static let service = "io.netnavi.keys"
    private static let privateKeyAccount = "wg_private_key"
    private static let publicKeyAccount  = "wg_public_key"

    // MARK: - Public API

    static func getKeyPair() throws -> (PrivateKey, PublicKey) {
        return try generateLocalKeyPairIfNeeded()
    }

    static func generateLocalKeyPairIfNeeded() throws -> (PrivateKey, PublicKey) {
        if let priv = loadPrivateKey(),
           let pub = loadPublicKey() {
            return (priv, pub)
        }

        let privateKey = PrivateKey()
        let publicKey = privateKey.publicKey

        try saveKey(privateKey.base64Key, account: privateKeyAccount)
        try saveKey(publicKey.base64Key, account: publicKeyAccount)

        return (privateKey, publicKey)
    }

    static func loadPrivateKey() -> PrivateKey? {
        guard let str = loadKey(account: privateKeyAccount) else { return nil }
        return PrivateKey(base64Key: str)
    }

    static func loadPublicKey() -> PublicKey? {
        guard let str = loadKey(account: publicKeyAccount) else { return nil }
        return PublicKey(base64Key: str)
    }

    static func deleteKeys() throws {
        try deleteKey(account: privateKeyAccount)
        try deleteKey(account: publicKeyAccount)
    }

    // MARK: - Keychain core

    private static func saveKey(_ value: String, account: String) throws {
        let data = value.data(using: .utf8)!

        let query: [String: Any] = [
            kSecClass as String : kSecClassGenericPassword,
            kSecAttrService as String : service,
            kSecAttrAccount as String : account
        ]

        SecItemDelete(query as CFDictionary)

        let insert: [String: Any] = [
            kSecClass as String       : kSecClassGenericPassword,
            kSecAttrService as String : service,
            kSecAttrAccount as String : account,
            kSecValueData as String   : data,
            kSecAttrAccessible as String : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: "Keychain", code: Int(status), userInfo: nil)
        }
    }

    private static func loadKey(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String       : kSecClassGenericPassword,
            kSecAttrService as String : service,
            kSecAttrAccount as String : account,
            kSecReturnData as String  : true,
            kSecMatchLimit as String : kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let str = String(data: data, encoding: .utf8)
        else { return nil }

        return str
    }

    private static func deleteKey(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String       : kSecClassGenericPassword,
            kSecAttrService as String : service,
            kSecAttrAccount as String : account
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw NSError(domain: "Keychain", code: Int(status), userInfo: nil)
        }
    }
}
