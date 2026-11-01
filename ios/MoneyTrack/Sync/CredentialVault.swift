import Foundation
import Security

@MainActor protocol CredentialVault {
    func read() throws -> SessionCredential?
    func write(_ credential: SessionCredential) throws
    func clear() throws
}

struct KeychainVault: CredentialVault {
    private let serviceSuffix: String
    init(serviceSuffix: String = ".session") { self.serviceSuffix = serviceSuffix }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "MoneyTrack") + serviceSuffix,
         kSecAttrAccount as String: "active"]
    }
    func read() throws -> SessionCredential? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw vaultError(status) }
        return try JSONDecoder().decode(SessionCredential.self, from: data)
    }
    func write(_ credential: SessionCredential) throws {
        let data = try JSONEncoder().encode(credential)
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
            guard status == errSecSuccess else { throw vaultError(status) }
        } else if status != errSecSuccess { throw vaultError(status) }
    }
    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw vaultError(status) }
    }
    private func vaultError(_ status: OSStatus) -> NSError {
        NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Couldn't access the saved account credential."])
    }
}

@MainActor final class EphemeralVault: CredentialVault {
    private var credential: SessionCredential?
    func read() throws -> SessionCredential? { credential }
    func write(_ credential: SessionCredential) throws { self.credential = credential }
    func clear() throws { credential = nil }
}
