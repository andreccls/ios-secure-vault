import Foundation
import LocalAuthentication
import Security

/// Stores the DEK as a Keychain item guarded by `SecAccessControl(.biometryCurrentSet)`:
/// - `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`: readable only while unlocked, never migrates to another device
///   or iCloud Keychain/backups;
/// - `.biometryCurrentSet`: invalidated if fingerprints/faces are added or removed (an attacker who enrolls their own
///   face on a stolen, passcode-unlocked phone cannot reuse it).
/// The Secure Enclave enforces the biometric check, but the DEK itself is ordinary key material (the SE only holds
/// EC keys). This type needs a real device/biometry, so it is excluded from automated coverage (docs/TESTING.md).
public struct KeychainBiometricKeyStore: BiometricKeyStore {
  private let service: String
  private let account = "vault-dek"

  public init(service: String = "dev.andrecoura.SecureVault.biometric") { self.service = service }

  public var isAvailable: Bool {
    var error: NSError?
    return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
  }

  private var baseQuery: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecUseDataProtectionKeychain as String: true,
    ]
  }

  public var hasStoredKey: Bool {
    let context = LAContext()
    context.interactionNotAllowed = true  // existence check must never prompt
    var query = baseQuery
    query[kSecUseAuthenticationContext as String] = context
    let status = SecItemCopyMatching(query as CFDictionary, nil)
    return status == errSecSuccess || status == errSecInteractionNotAllowed
  }

  public func save(key: Data) throws {
    deleteKey()
    var accessError: Unmanaged<CFError>?
    guard
      let access = SecAccessControlCreateWithFlags(
        nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .biometryCurrentSet, &accessError)
    else { throw BiometricError.unavailable }
    var query = baseQuery
    query[kSecAttrAccessControl as String] = access
    query[kSecValueData as String] = key
    guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw BiometricError.failed }
  }

  public func loadKey(reason: String) async throws -> Data {
    let context = LAContext()
    do {
      try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
    } catch let error as LAError
      where error.code == .userCancel || error.code == .appCancel || error.code == .systemCancel
    {
      throw BiometricError.cancelled
    } catch {
      throw BiometricError.failed
    }
    var query = baseQuery
    query[kSecReturnData as String] = true
    query[kSecUseAuthenticationContext as String] = context  // already authenticated: no second prompt
    var result: CFTypeRef?
    switch SecItemCopyMatching(query as CFDictionary, &result) {
    case errSecSuccess: return (result as? Data) ?? Data()
    case errSecItemNotFound: throw BiometricError.notFound
    default: throw BiometricError.failed
    }
  }

  public func deleteKey() { SecItemDelete(baseQuery as CFDictionary) }
}
