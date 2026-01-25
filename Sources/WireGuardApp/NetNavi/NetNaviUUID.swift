//
//
import Security
import Foundation

final class DeviceUUID {

    private static let service = "io.netnavi.deviceuuid"
    private static let account = "freecomm"

    static func get() -> String {
        if let existing = read() {
            return existing
        }

        let newID = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        save(newID)
        return newID
    }

    // MARK: - Keychain

    private static func save(_ value: String) {
        let data = Data(value.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]

        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        return string
    }
}

