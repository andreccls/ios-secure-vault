import CryptoKit
import Foundation

public enum VaultError: Error, Equatable {
  case alreadyInitialized
  case notInitialized
  case locked
  case wrongPassword
  case weakPassword
  case throttled(retryAfter: TimeInterval)
  case corruptedRecord
}

/// The encrypted vault. Key hierarchy (ADR 0004):
///
///     master password --PBKDF2(salt, iterations)--> KEK --AES-GCM--> wrappedDEK (stored in the header)
///     DEK (random 256-bit) --AES-GCM, AAD = item id--> one ciphertext blob per item
///
/// Being an actor gives mutually exclusive access to the unlocked DEK. The DEK only exists in memory while unlocked.
public actor Vault {
  public static let minimumPasswordLength = 8
  private static let kdfName = "pbkdf2-hmac-sha256"
  private static let dekAAD = Data("securevault.dek.v1".utf8)
  private static let checkAAD = Data("securevault.check.v1".utf8)
  private static let checkPlaintext = Data("securevault".utf8)

  private let storage: VaultStorage
  private let iterations: Int
  private let policy: AttemptPolicy
  private let now: @Sendable () -> Date
  private var dek: SymmetricKey?

  public init(
    storage: VaultStorage, kdfIterations: Int = PBKDF2.defaultIterations,
    policy: AttemptPolicy = AttemptPolicy(),
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.storage = storage
    self.iterations = kdfIterations
    self.policy = policy
    self.now = now
  }

  public var isUnlocked: Bool { dek != nil }

  public func isInitialized() throws -> Bool { try storage.loadHeader() != nil }

  // MARK: Lifecycle

  public func create(masterPassword: String) throws {
    guard try storage.loadHeader() == nil else { throw VaultError.alreadyInitialized }
    guard masterPassword.count >= Self.minimumPasswordLength else { throw VaultError.weakPassword }
    let newDEK = SymmetricKey(size: .bits256)
    let salt = PBKDF2.randomSalt()
    let kek = try PBKDF2.deriveKey(password: masterPassword, salt: salt, iterations: iterations)
    let header = VaultHeader(
      version: 1, kdf: Self.kdfName, iterations: iterations, salt: salt,
      wrappedDEK: try AESGCMCipher.seal(Self.bytes(of: newDEK), key: kek, aad: Self.dekAAD),
      keyCheck: try AESGCMCipher.seal(Self.checkPlaintext, key: newDEK, aad: Self.checkAAD))
    try storage.saveHeader(header)
    dek = newDEK
  }

  public func unlock(masterPassword: String) throws {
    guard let header = try storage.loadHeader() else { throw VaultError.notInitialized }
    var attempts = try storage.loadAttempts()
    let wait = policy.retryAfter(attempts, now: now())
    guard wait == 0 else { throw VaultError.throttled(retryAfter: wait) }
    do {
      dek = try Self.unwrapDEK(header: header, password: masterPassword)
    } catch VaultError.wrongPassword {
      attempts.failures += 1
      attempts.lastFailure = now()
      try storage.saveAttempts(attempts)
      throw VaultError.wrongPassword
    }
    if attempts != AttemptState() { try storage.saveAttempts(AttemptState()) }
  }

  /// Unlock with a DEK obtained from the biometric keychain. Not subject to the backoff: the OS rate-limits biometrics.
  public func unlock(key: Data) throws {
    guard let header = try storage.loadHeader() else { throw VaultError.notInitialized }
    let candidate = SymmetricKey(data: key)
    guard
      (try? AESGCMCipher.open(header.keyCheck, key: candidate, aad: Self.checkAAD)) == Self.checkPlaintext
    else { throw VaultError.wrongPassword }
    dek = candidate
  }

  public func lock() { dek = nil }

  /// Raw DEK for biometric enrollment. Only callable while unlocked (the user just proved the master password).
  public func exportKey() throws -> Data {
    guard let dek else { throw VaultError.locked }
    return Self.bytes(of: dek)
  }

  /// Only the wrapped DEK changes; items keep their ciphertext because the DEK stays the same.
  public func changeMasterPassword(current: String, new: String) throws {
    guard let dek else { throw VaultError.locked }
    guard new.count >= Self.minimumPasswordLength else { throw VaultError.weakPassword }
    guard var header = try storage.loadHeader() else { throw VaultError.notInitialized }
    _ = try Self.unwrapDEK(header: header, password: current)
    let salt = PBKDF2.randomSalt()
    let kek = try PBKDF2.deriveKey(password: new, salt: salt, iterations: iterations)
    header.salt = salt
    header.iterations = iterations
    header.wrappedDEK = try AESGCMCipher.seal(Self.bytes(of: dek), key: kek, aad: Self.dekAAD)
    try storage.saveHeader(header)
  }

  // MARK: Items

  public func items() throws -> [VaultItem] {
    guard let dek else { throw VaultError.locked }
    return try storage.loadRecords().map { id, blob in
      do {
        return try JSONDecoder().decode(
          VaultItem.self, from: AESGCMCipher.open(blob, key: dek, aad: Self.itemAAD(id)))
      } catch {
        throw VaultError.corruptedRecord
      }
    }.sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
  }

  public func save(_ item: VaultItem) throws {
    guard let dek else { throw VaultError.locked }
    let blob = try AESGCMCipher.seal(JSONEncoder().encode(item), key: dek, aad: Self.itemAAD(item.id))
    try storage.saveRecord(blob, id: item.id)
  }

  public func delete(id: UUID) throws {
    guard dek != nil else { throw VaultError.locked }
    try storage.deleteRecord(id: id)
  }

  /// Merges decrypted backup items (same id overwrites). Returns how many were written.
  public func importItems(_ items: [VaultItem]) throws -> Int {
    for item in items { try save(item) }
    return items.count
  }

  // MARK: Helpers

  private static func unwrapDEK(header: VaultHeader, password: String) throws -> SymmetricKey {
    let kek = try PBKDF2.deriveKey(password: password, salt: header.salt, iterations: header.iterations)
    do {
      return SymmetricKey(data: try AESGCMCipher.open(header.wrappedDEK, key: kek, aad: dekAAD))
    } catch CipherError.authenticationFailed {
      throw VaultError.wrongPassword
    } catch {
      throw VaultError.corruptedRecord
    }
  }

  private static func itemAAD(_ id: UUID) -> Data {
    Data("securevault.item.v1".utf8) + withUnsafeBytes(of: id.uuid) { Data($0) }
  }

  private static func bytes(of key: SymmetricKey) -> Data { key.withUnsafeBytes { Data($0) } }
}
