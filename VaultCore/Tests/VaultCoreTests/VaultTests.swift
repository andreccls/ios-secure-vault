import CryptoKit
import Foundation
import Testing

@testable import VaultCore

/// Mutable test clock shared with the actor under test.
final class TestClock: @unchecked Sendable {
  private let lock = NSLock()
  private var current = Date(timeIntervalSince1970: 1_700_000_000)
  var now: Date { lock.withLock { current } }
  func advance(_ seconds: TimeInterval) { lock.withLock { current.addTimeInterval(seconds) } }
}

func makeVault(
  storage: VaultStorage = InMemoryVaultStorage(), clock: TestClock = TestClock()
) -> Vault {
  // Low iteration count keeps the suite fast; PBKDF2 itself is covered by known-answer vectors.
  Vault(storage: storage, kdfIterations: 10, now: { clock.now })
}

let sampleItem = VaultItem(
  title: "Example login",
  content: .password(
    PasswordContent(username: "alice", password: "hunter2-example", url: "https://example.com")))

@Suite("Vault lifecycle")
struct VaultLifecycleTests {
  @Test func createUnlocksAndPersistsHeader() async throws {
    let storage = InMemoryVaultStorage()
    let vault = makeVault(storage: storage)
    #expect(try await vault.isInitialized() == false)
    try await vault.create(masterPassword: "correct horse battery")
    #expect(try await vault.isInitialized())
    #expect(await vault.isUnlocked)
    let header = try #require(try storage.loadHeader())
    #expect(header.iterations == 10)
    #expect(header.salt.count == PBKDF2.saltLength)
  }

  @Test func createTwiceFails() async throws {
    let vault = makeVault()
    try await vault.create(masterPassword: "correct horse battery")
    await #expect(throws: VaultError.alreadyInitialized) {
      try await vault.create(masterPassword: "another password")
    }
  }

  @Test func shortMasterPasswordIsRejected() async {
    let vault = makeVault()
    await #expect(throws: VaultError.weakPassword) { try await vault.create(masterPassword: "short") }
  }

  @Test func unlockBeforeCreateFails() async {
    await #expect(throws: VaultError.notInitialized) {
      try await makeVault().unlock(masterPassword: "whatever-pass")
    }
  }

  @Test func lockThenUnlockWithCorrectPassword() async throws {
    let storage = InMemoryVaultStorage()
    let vault = makeVault(storage: storage)
    try await vault.create(masterPassword: "correct horse battery")
    try await vault.save(sampleItem)
    await vault.lock()
    #expect(await vault.isUnlocked == false)
    await #expect(throws: VaultError.locked) { try await vault.items() }

    // A brand new actor over the same storage (app relaunch) can unlock and read everything.
    let reopened = makeVault(storage: storage)
    try await reopened.unlock(masterPassword: "correct horse battery")
    #expect(try await reopened.items() == [sampleItem])
  }

  @Test func wrongPasswordFailsAndStaysLocked() async throws {
    let vault = makeVault()
    try await vault.create(masterPassword: "correct horse battery")
    await vault.lock()
    await #expect(throws: VaultError.wrongPassword) {
      try await vault.unlock(masterPassword: "wrong horse battery")
    }
    #expect(await vault.isUnlocked == false)
  }

  @Test func dekIsRandomPerVaultAndWrappedNotStoredInClear() async throws {
    let a = InMemoryVaultStorage()
    let b = InMemoryVaultStorage()
    try await makeVault(storage: a).create(masterPassword: "same password here")
    try await makeVault(storage: b).create(masterPassword: "same password here")
    let headerA = try #require(try a.loadHeader())
    let headerB = try #require(try b.loadHeader())
    #expect(headerA.wrappedDEK != headerB.wrappedDEK)
    #expect(headerA.salt != headerB.salt)
  }
}

@Suite("Vault items")
struct VaultItemTests {
  @Test func crudRoundTrip() async throws {
    let vault = makeVault()
    try await vault.create(masterPassword: "correct horse battery")
    try await vault.save(sampleItem)
    var edited = sampleItem
    edited.title = "Renamed"
    edited.isFavorite = true
    try await vault.save(edited)
    #expect(try await vault.items() == [edited])
    try await vault.delete(id: sampleItem.id)
    #expect(try await vault.items().isEmpty)
  }

  @Test func allThreeKindsRoundTrip() async throws {
    let vault = makeVault()
    try await vault.create(masterPassword: "correct horse battery")
    let totp = try AuthenticatorContent(issuer: "Example", account: "a@example.com", secretInput: "GEZDGNBV")
    let items = [
      sampleItem,
      VaultItem(title: "OTP", content: .authenticator(totp)),
      VaultItem(
        title: "CI token",
        content: .authKey(AuthKeyContent(keyKind: .token, secret: "tok_EXAMPLE", notes: "n"))),
    ]
    for item in items { try await vault.save(item) }
    #expect(Set(try await vault.items()) == Set(items))
  }

  @Test func nothingSensitiveIsStoredInClear() async throws {
    let storage = InMemoryVaultStorage()
    let vault = makeVault(storage: storage)
    try await vault.create(masterPassword: "correct horse battery")
    try await vault.save(sampleItem)
    let blob = try #require(try storage.loadRecords()[sampleItem.id])
    for needle in ["Example login", "alice", "hunter2-example", "example.com"] {
      #expect(blob.range(of: Data(needle.utf8)) == nil)
    }
  }

  @Test func savingTheSameItemTwiceUsesDifferentNonces() async throws {
    let storage = InMemoryVaultStorage()
    let vault = makeVault(storage: storage)
    try await vault.create(masterPassword: "correct horse battery")
    try await vault.save(sampleItem)
    let first = try #require(try storage.loadRecords()[sampleItem.id])
    try await vault.save(sampleItem)
    let second = try #require(try storage.loadRecords()[sampleItem.id])
    #expect(first != second)
    #expect(first.prefix(12) != second.prefix(12))
  }

  @Test func tamperedBlobIsDetected() async throws {
    let storage = InMemoryVaultStorage()
    let vault = makeVault(storage: storage)
    try await vault.create(masterPassword: "correct horse battery")
    try await vault.save(sampleItem)
    var blob = try #require(try storage.loadRecords()[sampleItem.id])
    blob[blob.count - 1] ^= 0xFF
    try storage.saveRecord(blob, id: sampleItem.id)
    await #expect(throws: VaultError.corruptedRecord) { try await vault.items() }
  }

  @Test func blobSwappedBetweenItemsIsDetectedThanksToAAD() async throws {
    let storage = InMemoryVaultStorage()
    let vault = makeVault(storage: storage)
    try await vault.create(masterPassword: "correct horse battery")
    let other = VaultItem(title: "Other", content: .password(PasswordContent(password: "x")))
    try await vault.save(sampleItem)
    try await vault.save(other)
    let blobA = try #require(try storage.loadRecords()[sampleItem.id])
    try storage.saveRecord(blobA, id: other.id)  // attacker copies A's ciphertext over B's slot
    await #expect(throws: VaultError.corruptedRecord) { try await vault.items() }
  }

  @Test func operationsRequireUnlock() async throws {
    let vault = makeVault()
    try await vault.create(masterPassword: "correct horse battery")
    await vault.lock()
    await #expect(throws: VaultError.locked) { try await vault.save(sampleItem) }
    await #expect(throws: VaultError.locked) { try await vault.delete(id: sampleItem.id) }
    await #expect(throws: VaultError.locked) { try await vault.exportKey() }
  }
}

@Suite("Master password change and key wrapping")
struct MasterPasswordTests {
  @Test func changePasswordRewrapsDEKWithoutTouchingItems() async throws {
    let storage = InMemoryVaultStorage()
    let vault = makeVault(storage: storage)
    try await vault.create(masterPassword: "old password 1")
    try await vault.save(sampleItem)
    let blobBefore = try #require(try storage.loadRecords()[sampleItem.id])
    let headerBefore = try #require(try storage.loadHeader())

    try await vault.changeMasterPassword(current: "old password 1", new: "new password 2")

    let headerAfter = try #require(try storage.loadHeader())
    #expect(headerAfter.salt != headerBefore.salt)
    #expect(headerAfter.wrappedDEK != headerBefore.wrappedDEK)
    #expect(try storage.loadRecords()[sampleItem.id] == blobBefore)  // DEK unchanged: no re-encryption needed

    await vault.lock()
    await #expect(throws: VaultError.wrongPassword) {
      try await vault.unlock(masterPassword: "old password 1")
    }
    try await vault.unlock(masterPassword: "new password 2")
    #expect(try await vault.items() == [sampleItem])
  }

  @Test func changePasswordChecksCurrentAndNewStrength() async throws {
    let vault = makeVault()
    try await vault.create(masterPassword: "old password 1")
    await #expect(throws: VaultError.wrongPassword) {
      try await vault.changeMasterPassword(current: "nope nope nope", new: "new password 2")
    }
    await #expect(throws: VaultError.weakPassword) {
      try await vault.changeMasterPassword(current: "old password 1", new: "short")
    }
    await vault.lock()
    await #expect(throws: VaultError.locked) {
      try await vault.changeMasterPassword(current: "old password 1", new: "new password 2")
    }
  }

  @Test func exportedKeyUnlocksTheVaultAndWrongKeyIsRejected() async throws {
    let storage = InMemoryVaultStorage()
    let vault = makeVault(storage: storage)
    try await vault.create(masterPassword: "correct horse battery")
    try await vault.save(sampleItem)
    let key = try await vault.exportKey()
    await vault.lock()

    await #expect(throws: VaultError.wrongPassword) {
      try await vault.unlock(key: Data(repeating: 1, count: 32))
    }
    try await vault.unlock(key: key)
    #expect(try await vault.items() == [sampleItem])
  }

  @Test func unlockWithKeyBeforeCreateFails() async {
    await #expect(throws: VaultError.notInitialized) {
      try await makeVault().unlock(key: Data(repeating: 1, count: 32))
    }
  }

  @Test func tamperedHeaderFailsToUnlock() async throws {
    let storage = InMemoryVaultStorage()
    let vault = makeVault(storage: storage)
    try await vault.create(masterPassword: "correct horse battery")
    var header = try #require(try storage.loadHeader())
    header.wrappedDEK[header.wrappedDEK.count - 1] ^= 1
    try storage.saveHeader(header)
    await vault.lock()
    await #expect(throws: VaultError.wrongPassword) {
      try await vault.unlock(masterPassword: "correct horse battery")
    }
  }

  @Test func malformedHeaderIsCorrupted() async throws {
    let storage = InMemoryVaultStorage()
    let vault = makeVault(storage: storage)
    try await vault.create(masterPassword: "correct horse battery")
    var header = try #require(try storage.loadHeader())
    header.wrappedDEK = Data([1, 2, 3])
    try storage.saveHeader(header)
    await vault.lock()
    await #expect(throws: VaultError.corruptedRecord) {
      try await vault.unlock(masterPassword: "correct horse battery")
    }
  }
}

@Suite("Wrong-attempt backoff")
struct ThrottleTests {
  @Test func policyDelaysGrowExponentiallyAndAreCapped() {
    let policy = AttemptPolicy()
    #expect(policy.delay(afterFailures: 0) == 0)
    #expect(policy.delay(afterFailures: 3) == 0)
    #expect(policy.delay(afterFailures: 4) == 2)
    #expect(policy.delay(afterFailures: 5) == 4)
    #expect(policy.delay(afterFailures: 6) == 8)
    #expect(policy.delay(afterFailures: 50) == 300)
  }

  @Test func retryAfterIsTheRemainingTime() {
    let policy = AttemptPolicy()
    let t0 = Date(timeIntervalSince1970: 100)
    let state = AttemptState(failures: 5, lastFailure: t0)  // 4 s delay
    #expect(policy.retryAfter(state, now: t0.addingTimeInterval(1)) == 3)
    #expect(policy.retryAfter(state, now: t0.addingTimeInterval(10)) == 0)
    #expect(policy.retryAfter(AttemptState(), now: t0) == 0)
  }

  @Test func vaultThrottlesAfterRepeatedFailuresAndRecoversWhenTimePasses() async throws {
    let clock = TestClock()
    let vault = makeVault(clock: clock)
    try await vault.create(masterPassword: "correct horse battery")
    await vault.lock()

    for _ in 0..<3 {
      await #expect(throws: VaultError.wrongPassword) {
        try await vault.unlock(masterPassword: "bad password!")
      }
    }
    // 4th failure arms a 2 s delay.
    await #expect(throws: VaultError.wrongPassword) {
      try await vault.unlock(masterPassword: "bad password!")
    }
    // Even the CORRECT password is refused while throttled (no oracle for an online brute force).
    await #expect(throws: VaultError.throttled(retryAfter: 2)) {
      try await vault.unlock(masterPassword: "correct horse battery")
    }
    clock.advance(2.5)
    try await vault.unlock(masterPassword: "correct horse battery")
    #expect(await vault.isUnlocked)
  }

  @Test func throttleStateSurvivesRelaunchAndResetsOnSuccess() async throws {
    let storage = InMemoryVaultStorage()
    let clock = TestClock()
    let vault = makeVault(storage: storage, clock: clock)
    try await vault.create(masterPassword: "correct horse battery")
    await vault.lock()
    for _ in 0..<4 {
      await #expect(throws: VaultError.wrongPassword) {
        try await vault.unlock(masterPassword: "bad password!")
      }
    }
    let relaunched = makeVault(storage: storage, clock: clock)
    await #expect(throws: VaultError.throttled(retryAfter: 2)) {
      try await relaunched.unlock(masterPassword: "correct horse battery")
    }
    clock.advance(3)
    try await relaunched.unlock(masterPassword: "correct horse battery")
    #expect(try storage.loadAttempts() == AttemptState())
  }
}

@Suite("Encrypted backup")
struct BackupTests {
  let items = [
    sampleItem,
    VaultItem(title: "Key", content: .authKey(AuthKeyContent(keyKind: .sshKey, secret: "FAKE-KEY-EXAMPLE"))),
  ]

  @Test func exportThenImportRoundTrips() throws {
    let data = try BackupService.export(items: items, password: "backup password", iterations: 10)
    #expect(try BackupService.open(data, password: "backup password") == items)
  }

  @Test func backupFileHidesContentsAndWrongPasswordFails() throws {
    let data = try BackupService.export(items: items, password: "backup password", iterations: 10)
    #expect(data.range(of: Data("hunter2-example".utf8)) == nil)
    #expect(throws: VaultError.wrongPassword) { try BackupService.open(data, password: "other password") }
  }

  @Test func tamperedOrGarbageBackupIsRejected() throws {
    #expect(throws: VaultError.corruptedRecord) {
      try BackupService.open(Data("not json".utf8), password: "x y z 1234")
    }
    let data = try BackupService.export(items: items, password: "backup password", iterations: 10)
    var envelope = try JSONDecoder().decode(BackupService.Envelope.self, from: data)
    envelope.sealed[envelope.sealed.count - 1] ^= 1
    let tampered = try JSONEncoder().encode(envelope)
    #expect(throws: VaultError.wrongPassword) {
      try BackupService.open(tampered, password: "backup password")
    }
    envelope.sealed = Data([1, 2])
    #expect(throws: VaultError.corruptedRecord) {
      try BackupService.open(try JSONEncoder().encode(envelope), password: "backup password")
    }
    envelope.iterations = 0
    #expect(throws: VaultError.corruptedRecord) {
      try BackupService.open(try JSONEncoder().encode(envelope), password: "backup password")
    }
  }

  @Test func validCiphertextWithUnexpectedPayloadIsCorrupted() throws {
    let salt = PBKDF2.randomSalt()
    let key = try PBKDF2.deriveKey(password: "backup password", salt: salt, iterations: 10)
    let sealed = try AESGCMCipher.seal(
      Data("{\"not\":\"items\"}".utf8), key: key, aad: Data("securevault.backup.v1".utf8))
    let data = try JSONEncoder().encode(
      BackupService.Envelope(version: 1, iterations: 10, salt: salt, sealed: sealed))
    #expect(throws: VaultError.corruptedRecord) { try BackupService.open(data, password: "backup password") }
  }

  @Test func weakBackupPasswordIsRejected() {
    #expect(throws: VaultError.weakPassword) {
      try BackupService.export(items: items, password: "short", iterations: 10)
    }
  }

  @Test func importIntoAnotherVaultMerges() async throws {
    let source = makeVault()
    try await source.create(masterPassword: "source password")
    for item in items { try await source.save(item) }
    let data = try BackupService.export(
      items: try await source.items(), password: "backup password", iterations: 10)

    let target = makeVault()
    try await target.create(masterPassword: "target password")
    #expect(try await target.importItems(BackupService.open(data, password: "backup password")) == 2)
    #expect(Set(try await target.items()) == Set(items))
  }
}
