import Foundation
import Security
public enum CredentialVault {
    private static let service = "net.codex-relay.operator"
    public static func save(_ credential: Credential) throws {
        let data = try RelayJSON.encoder().encode(credential)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "hub"]
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecItemNotFound {
            var insert = query; insert[kSecValueData as String] = data; insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw HubFailure.message(String(localized: "Unable to save access securely in Keychain.", bundle: relayLocalizationBundle)) }
        } else if update != errSecSuccess { throw HubFailure.message(String(localized: "Keychain unavailable.", bundle: relayLocalizationBundle)) }
    }
    public static func load() -> Credential? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "hub", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?; guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? RelayJSON.decoder().decode(Credential.self, from: data)
    }
    public static func clear() { SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "hub"] as CFDictionary) }
}
