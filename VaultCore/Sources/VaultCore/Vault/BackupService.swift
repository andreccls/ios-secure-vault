import CryptoKit
import Foundation

/// Password-protected export/import: a JSON envelope {version, kdf params, salt, AES-GCM(items)}. The backup password
/// is independent from the master password, so a backup does not reveal (or depend on) the vault's keys.
public enum BackupService {
  struct Envelope: Codable {
    var version: Int
    var iterations: Int
    var salt: Data
    var sealed: Data
  }

  private static let aad = Data("securevault.backup.v1".utf8)
  private static let iterationBounds = 1...10_000_000  // a crafted file must not stall the KDF forever

  public static func export(
    items: [VaultItem], password: String, iterations: Int = PBKDF2.defaultIterations
  ) throws -> Data {
    guard password.count >= Vault.minimumPasswordLength else { throw VaultError.weakPassword }
    let salt = PBKDF2.randomSalt()
    let key = try PBKDF2.deriveKey(password: password, salt: salt, iterations: iterations)
    let sealed = try AESGCMCipher.seal(JSONEncoder().encode(items), key: key, aad: aad)
    return try JSONEncoder().encode(Envelope(version: 1, iterations: iterations, salt: salt, sealed: sealed))
  }

  public static func open(_ data: Data, password: String) throws -> [VaultItem] {
    guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
      envelope.version == 1, iterationBounds.contains(envelope.iterations), !envelope.salt.isEmpty
    else { throw VaultError.corruptedRecord }
    let key = try PBKDF2.deriveKey(password: password, salt: envelope.salt, iterations: envelope.iterations)
    let plaintext: Data
    do {
      plaintext = try AESGCMCipher.open(envelope.sealed, key: key, aad: aad)
    } catch CipherError.authenticationFailed {
      throw VaultError.wrongPassword
    } catch {
      throw VaultError.corruptedRecord
    }
    guard let items = try? JSONDecoder().decode([VaultItem].self, from: plaintext) else {
      throw VaultError.corruptedRecord
    }
    return items
  }
}
