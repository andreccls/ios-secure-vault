import Foundation
import Testing
import VaultCore

@testable import SecureVault

final class FakeBiometrics: BiometricKeyStore, @unchecked Sendable {
  var available = true
  var stored: Data?
  var failLoad: BiometricError?
  var isAvailable: Bool { available }
  var hasStoredKey: Bool { stored != nil }
  func save(key: Data) throws { stored = key }
  func loadKey(reason: String) async throws -> Data {
    if let failLoad { throw failLoad }
    guard let stored else { throw BiometricError.notFound }
    return stored
  }
  func deleteKey() { stored = nil }
}

final class MutableClock: @unchecked Sendable {
  private let lock = NSLock()
  private var date = Date(timeIntervalSince1970: 1_700_000_000)
  var now: Date { lock.withLock { date } }
  func advance(_ seconds: TimeInterval) { lock.withLock { date.addTimeInterval(seconds) } }
}

@MainActor
private func makeSession(
  biometrics: FakeBiometrics = FakeBiometrics(), clock: MutableClock = MutableClock(),
  storage: VaultStorage = InMemoryVaultStorage()
) -> SessionModel {
  let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
  let vault = Vault(storage: storage, kdfIterations: 10, now: { clock.now })
  return SessionModel(vault: vault, biometrics: biometrics, defaults: defaults, now: { clock.now })
}

private let pw = "correct horse battery"

@MainActor
private func unlockedSession(
  biometrics: FakeBiometrics = FakeBiometrics(), clock: MutableClock = MutableClock()
) async -> SessionModel {
  let session = makeSession(biometrics: biometrics, clock: clock)
  await session.bootstrap()
  await session.createVault(password: pw, confirmation: pw)
  return session
}

@MainActor
@Suite("SessionModel")
struct SessionModelTests {
  @Test func bootstrapGoesToSetupThenLocked() async {
    let storage = InMemoryVaultStorage()
    let first = makeSession(storage: storage)
    #expect(first.phase == .loading)
    await first.bootstrap()
    #expect(first.phase == .setup)
    await first.createVault(password: pw, confirmation: pw)
    #expect(first.phase == .unlocked)
    let second = makeSession(storage: storage)
    await second.bootstrap()
    #expect(second.phase == .locked)
  }

  @Test func createRequiresMatchingStrongPassword() async {
    let session = makeSession()
    await session.bootstrap()
    #expect(await session.createVault(password: pw, confirmation: "other") == false)
    #expect(session.errorMessage == "As senhas não coincidem.")
    #expect(await session.createVault(password: "short", confirmation: "short") == false)
    #expect(session.errorMessage?.contains("pelo menos") == true)
    #expect(session.phase == .setup)
  }

  @Test func lockClearsItemsAndUnlockRestoresThem() async {
    let session = await unlockedSession()
    _ = await session.save(VaultItem(title: "A", content: .password(PasswordContent(password: "x"))))
    #expect(session.items.count == 1)
    session.lock()
    #expect(session.phase == .locked)
    #expect(session.items.isEmpty)
    #expect(await session.unlock(password: pw))
    #expect(session.items.map(\.title) == ["A"])
  }

  @Test func wrongPasswordShowsErrorAndStaysLocked() async {
    let session = await unlockedSession()
    session.lock()
    #expect(await session.unlock(password: "wrong password") == false)
    #expect(session.errorMessage == "Senha incorreta.")
    #expect(session.phase == .locked)
  }

  @Test func repeatedFailuresShowThrottleMessage() async {
    let session = await unlockedSession()
    session.lock()
    for _ in 0..<4 { _ = await session.unlock(password: "wrong password") }
    _ = await session.unlock(password: pw)
    #expect(session.errorMessage?.hasPrefix("Muitas tentativas") == true)
    #expect(session.phase == .locked)
  }

  @Test func crudAndFavorite() async {
    let session = await unlockedSession()
    let item = VaultItem(title: "A", content: .password(PasswordContent()))
    #expect(await session.save(item))
    var renamed = item
    renamed.title = "B"
    #expect(await session.save(renamed))
    #expect(session.items.map(\.title) == ["B"])
    await session.toggleFavorite(renamed)
    #expect(session.item(id: item.id)?.isFavorite == true)
    await session.delete(id: item.id)
    #expect(session.items.isEmpty)
    #expect(session.item(id: item.id) == nil)
  }

  @Test func backgroundLocksImmediately() async {
    let session = await unlockedSession()
    session.handleBackground()
    #expect(session.phase == .locked)
  }

  @Test func inactivityLocksOnlyAfterTheTimeout() async {
    let clock = MutableClock()
    let session = await unlockedSession(clock: clock)
    session.autoLockTimeout = .thirtySeconds
    clock.advance(20)
    session.recordActivity()
    clock.advance(20)
    session.checkInactivity()
    #expect(session.phase == .unlocked)
    clock.advance(11)
    session.checkInactivity()
    #expect(session.phase == .locked)
  }

  @Test func biometricsEnableUnlockAndDisable() async {
    let bio = FakeBiometrics()
    let session = await unlockedSession(biometrics: bio)
    await session.enableBiometrics()
    #expect(session.biometricsEnabled)
    #expect(bio.stored != nil)
    session.lock()
    await session.unlockWithBiometrics()
    #expect(session.phase == .unlocked)
    session.lock()
    session.disableBiometrics()
    #expect(bio.stored == nil)
    await session.unlockWithBiometrics()
    #expect(session.phase == .locked)
  }

  @Test func biometricsUnavailableAndFailureFallbacks() async {
    let bio = FakeBiometrics()
    bio.available = false
    let session = await unlockedSession(biometrics: bio)
    await session.enableBiometrics()
    #expect(session.biometricsEnabled == false)
    #expect(session.errorMessage != nil)

    bio.available = true
    await session.enableBiometrics()
    session.lock()
    bio.failLoad = .cancelled
    await session.unlockWithBiometrics()
    #expect(session.phase == .locked && session.biometricsEnabled)  // cancel keeps biometrics enabled
    bio.failLoad = .failed
    await session.unlockWithBiometrics()
    #expect(session.phase == .locked && !session.biometricsEnabled)  // failure falls back to password
  }

  @Test func changeMasterPassword() async {
    let session = await unlockedSession()
    #expect(
      await session.changeMasterPassword(current: pw, new: "new password 2", confirmation: "nope") == false)
    #expect(
      await session.changeMasterPassword(
        current: "bad bad bad", new: "new password 2", confirmation: "new password 2") == false)
    #expect(
      await session.changeMasterPassword(current: pw, new: "new password 2", confirmation: "new password 2"))
    session.lock()
    #expect(await session.unlock(password: "new password 2"))
  }

  @Test func backupRoundTripBetweenSessions() async throws {
    let source = await unlockedSession()
    _ = await source.save(VaultItem(title: "Keep", content: .authKey(AuthKeyContent(secret: "FAKE"))))
    #expect(await source.exportBackup(password: "short") == nil)
    let data = try #require(await source.exportBackup(password: "backup password"))
    let target = await unlockedSession()
    #expect(await target.importBackup(data, password: "wrong password") == nil)
    #expect(await target.importBackup(data, password: "backup password") == 1)
    #expect(target.items.map(\.title) == ["Keep"])
  }

  @Test func messagesCoverEveryVaultError() {
    let errors: [VaultError] = [
      .wrongPassword, .weakPassword, .throttled(retryAfter: 1.2), .corruptedRecord, .locked,
      .alreadyInitialized,
      .notInitialized,
    ]
    #expect(Set(errors.map { SessionModel.message(for: $0) }).count == errors.count)
    #expect(SessionModel.message(for: CocoaError(.fileNoSuchFile)) == "Não foi possível concluir a operação.")
  }
}
