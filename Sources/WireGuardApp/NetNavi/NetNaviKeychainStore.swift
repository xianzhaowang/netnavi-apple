//
//
import Security
import Foundation

final class NetNaviKeychainStore {

    static let shared = NetNaviKeychainStore()
    private init() {}

    private let service = "io.netnavi.securestore"

    // MARK: - Public API

    func set(_ value: String, for key: String) {
        let data = Data(value.utf8)

        if exists(key) {
            // update(data, key)
        } else {
            add(data, key)
        }
    }

    func update(_ value: String, for key: String) {
        let data = Data(value.utf8)

        if exists(key) {
            update(data, key)
        }
    }

    func get(_ key: String) -> String? {
        let query: [String: Any] = baseQuery(key)
        var item: AnyObject?

        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    func delete(_ key: String) {
        SecItemDelete(baseQuery(key) as CFDictionary)
    }

    func setNetNaviConfig(_ data: Data, for key: String) {
        if exists(key) {
            update(data, key)
        } else {
            add(data, key)
        }
    }

    // Retrieve raw Data
    func getNetNaviConfig(_ key: String) -> Data? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return (status == errSecSuccess) ? (item as? Data) : nil
    }

    // MARK: - Internal

    private func exists(_ key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: false
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    private func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }

    private func add(_ data: Data, _ key: String) {
        var query = baseQuery(key)
        query[kSecValueData as String] = data
        SecItemAdd(query as CFDictionary, nil)
    }

    private func update(_ data: Data, _ key: String) {
        let query = baseQuery(key)
        let attributes = [kSecValueData as String: data]
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }
}
