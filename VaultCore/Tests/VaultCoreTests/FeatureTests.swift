import Foundation
import Testing

@testable import VaultCore

@Suite("Password generator")
struct PasswordGeneratorTests {
  @Test(arguments: [8, 16, 32, 64])
  func honorsLength(length: Int) throws {
    let value = try PasswordGenerator.generate(.init(length: length))
    #expect(value.count == length)
  }

  @Test func clampsLengthToSupportedRange() throws {
    #expect(
      try PasswordGenerator.generate(.init(length: 1)).count
        == PasswordGeneratorOptions.lengthRange.lowerBound)
    #expect(
      try PasswordGenerator.generate(.init(length: 999)).count
        == PasswordGeneratorOptions.lengthRange.upperBound)
  }

  @Test func containsAtLeastOneCharacterOfEachSelectedClass() throws {
    for _ in 0..<200 {
      let value = try PasswordGenerator.generate(.init(length: 8))
      #expect(value.contains { $0.isLowercase })
      #expect(value.contains { $0.isUppercase })
      #expect(value.contains { $0.isNumber })
      #expect(value.contains { PasswordGenerator.symbols.contains($0) })
    }
  }

  @Test func onlyUsesSelectedClasses() throws {
    let value = try PasswordGenerator.generate(
      .init(length: 64, lowercase: false, uppercase: false, digits: true, symbols: false))
    #expect(value.allSatisfy { $0.isNumber })
  }

  @Test func avoidsAmbiguousCharactersWhenAsked() throws {
    for _ in 0..<100 {
      let value = try PasswordGenerator.generate(.init(length: 64, avoidAmbiguous: true))
      #expect(value.allSatisfy { !PasswordGenerator.ambiguous.contains($0) })
    }
  }

  @Test func failsWithoutAnyCharacterClass() {
    #expect(throws: PasswordGeneratorError.noCharacterClass) {
      try PasswordGenerator.generate(.init(lowercase: false, uppercase: false, digits: false, symbols: false))
    }
  }

  @Test func generatedValuesDiffer() throws {
    let values = Set(try (0..<100).map { _ in try PasswordGenerator.generate(.init(length: 20)) })
    #expect(values.count == 100)
  }

  @Test func isDeterministicForAGivenGenerator() throws {
    struct Counter: RandomNumberGenerator {
      var state: UInt64 = 42
      mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
      }
    }
    var a = Counter()
    var b = Counter()
    #expect(
      try PasswordGenerator.generate(.init(), using: &a)
        == (try PasswordGenerator.generate(.init(), using: &b)))
  }

  @Test func entropyEstimateMatchesLengthTimesLog2OfPool() {
    let digitsOnly = PasswordGeneratorOptions(
      length: 10, lowercase: false, uppercase: false, digits: true, symbols: false)
    #expect(abs(PasswordGenerator.entropyBits(digitsOnly) - 10 * log2(10.0)) < 0.001)
    #expect(
      PasswordGenerator.entropyBits(.init(lowercase: false, uppercase: false, digits: false, symbols: false))
        == 0)
    #expect(
      PasswordGenerator.entropyBits(.init(length: 20)) > PasswordGenerator.entropyBits(.init(length: 12)))
  }
}

@Suite("Password strength")
struct PasswordStrengthTests {
  @Test func ranksByLengthAndVariety() {
    #expect(PasswordStrength.evaluate("").level == .veryWeak)
    #expect(PasswordStrength.evaluate("abc").level == .veryWeak)
    #expect(PasswordStrength.evaluate("abcdefgh").level == .weak)
    #expect(PasswordStrength.evaluate("Abcdefgh1").level == .fair)
    #expect(PasswordStrength.evaluate("Tr0ub4dor&3").level == .good)
    #expect(PasswordStrength.evaluate("correct-Horse-battery-9-staple!").level == .strong)
  }

  @Test func commonPasswordsAreAlwaysVeryWeak() {
    #expect(PasswordStrength.evaluate("Password123").level == .veryWeak)
    #expect(PasswordStrength.evaluate("qwertyuiop").level == .veryWeak)
  }

  @Test func repeatedCharactersDoNotInflateTheScore() {
    #expect(PasswordStrength.evaluate("aaaaaaaaaaaaaaaaaaaa").level <= .weak)
  }

  @Test func generatedDefaultPasswordIsStrong() throws {
    #expect(PasswordStrength.evaluate(try PasswordGenerator.generate(.init())).level == .strong)
  }
}

@Suite("Auto-lock")
struct AutoLockTests {
  let t0 = Date(timeIntervalSince1970: 1000)

  @Test func expiresOnlyAfterTheTimeoutOfInactivity() {
    let monitor = InactivityMonitor(timeout: .oneMinute, now: t0)
    #expect(!monitor.isExpired(at: t0.addingTimeInterval(59)))
    #expect(monitor.isExpired(at: t0.addingTimeInterval(60)))
  }

  @Test func activityPostponesTheLock() {
    var monitor = InactivityMonitor(timeout: .thirtySeconds, now: t0)
    monitor.recordActivity(at: t0.addingTimeInterval(20))
    #expect(!monitor.isExpired(at: t0.addingTimeInterval(49)))
    #expect(monitor.isExpired(at: t0.addingTimeInterval(50)))
  }

  @Test func changingTheTimeoutAppliesImmediately() {
    var monitor = InactivityMonitor(timeout: .fifteenMinutes, now: t0)
    #expect(!monitor.isExpired(at: t0.addingTimeInterval(120)))
    monitor.timeout = .thirtySeconds
    #expect(monitor.isExpired(at: t0.addingTimeInterval(120)))
  }

  @Test func clockGoingBackwardsNeverLocksEarly() {
    let monitor = InactivityMonitor(timeout: .thirtySeconds, now: t0)
    #expect(!monitor.isExpired(at: t0.addingTimeInterval(-500)))
  }

  @Test func timeoutsHaveHumanSecondsAndAreOrdered() {
    #expect(AutoLockTimeout.allCases.map(\.seconds) == [30, 60, 300, 900])
  }
}

@Suite("Item filter")
struct ItemFilterTests {
  let items: [VaultItem] = [
    VaultItem(
      title: "Zeta bank",
      content: .password(
        PasswordContent(username: "maria", password: "SECRETVALUE", url: "https://bank.example"))),
    VaultItem(title: "alpha mail", isFavorite: true, content: .password(PasswordContent(username: "joao"))),
    VaultItem(title: "Café", content: .authKey(AuthKeyContent(keyKind: .sshKey, secret: "SECRETVALUE"))),
    VaultItem(
      title: "VPN",
      content: .authenticator(
        try! AuthenticatorContent(issuer: "Contoso", account: "ana@contoso.example", secretInput: "GEZDGNBV"))
    ),
  ]

  @Test func favoritesComeFirstThenAlphabetical() {
    #expect(ItemFilter().apply(to: items).map(\.title) == ["alpha mail", "Café", "VPN", "Zeta bank"])
  }

  @Test func filtersByKind() {
    #expect(ItemFilter(kind: .authKey).apply(to: items).map(\.title) == ["Café"])
  }

  @Test func searchesTitleUsernameUrlIssuerAccentAndCaseInsensitively() {
    #expect(ItemFilter(query: "MARIA").apply(to: items).count == 1)
    #expect(ItemFilter(query: "bank.example").apply(to: items).count == 1)
    #expect(ItemFilter(query: "contoso").apply(to: items).map(\.title) == ["VPN"])
    #expect(ItemFilter(query: "cafe").apply(to: items).map(\.title) == ["Café"])
    #expect(ItemFilter(query: "ssh").apply(to: items).map(\.title) == ["Café"])
  }

  @Test func neverSearchesSecretValues() {
    #expect(ItemFilter(query: "SECRETVALUE").apply(to: items).isEmpty)
  }

  @Test func favoritesOnly() {
    #expect(ItemFilter(favoritesOnly: true).apply(to: items).map(\.title) == ["alpha mail"])
  }
}

@Suite("File storage")
struct FileStorageTests {
  func makeDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("vault-\(UUID().uuidString)")
  }

  @Test func persistsHeaderRecordsAndAttemptsAcrossInstances() async throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let vault = Vault(storage: FileVaultStorage(directory: directory), kdfIterations: 10)
    try await vault.create(masterPassword: "correct horse battery")
    try await vault.save(sampleItem)
    try await vault.save(VaultItem(title: "Second", content: .password(PasswordContent())))
    try await vault.delete(id: sampleItem.id)

    let reopened = Vault(storage: FileVaultStorage(directory: directory), kdfIterations: 10)
    #expect(try await reopened.isInitialized())
    try await reopened.unlock(masterPassword: "correct horse battery")
    #expect(try await reopened.items().map(\.title) == ["Second"])
  }

  @Test func emptyDirectoryMeansNotInitialized() throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let storage = FileVaultStorage(directory: directory)
    #expect(try storage.loadHeader() == nil)
    #expect(try storage.loadRecords().isEmpty)
    #expect(try storage.loadAttempts() == AttemptState())
    try storage.deleteRecord(id: UUID())  // deleting a missing record is a no-op
  }

  @Test func directoryIsExcludedFromBackupAndUnrelatedFilesAreIgnored() throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let storage = FileVaultStorage(directory: directory)
    try storage.saveRecord(Data([1, 2, 3]), id: UUID())
    try Data([9]).write(to: directory.appendingPathComponent("stray.txt"))
    try Data([9]).write(to: directory.appendingPathComponent("not-a-uuid.item"))
    let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
    #expect(values.isExcludedFromBackup == true)
    #expect(try storage.loadRecords().count == 1)
  }

  @Test func wipeRemovesEverything() async throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let storage = FileVaultStorage(directory: directory)
    let vault = Vault(storage: storage, kdfIterations: 10)
    try await vault.create(masterPassword: "correct horse battery")
    try storage.wipe()
    #expect(try storage.loadHeader() == nil)
    try storage.wipe()  // idempotent
  }

  @Test func attemptStateIsPersistedOnDisk() throws {
    let directory = makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let storage = FileVaultStorage(directory: directory)
    let state = AttemptState(failures: 4, lastFailure: Date(timeIntervalSince1970: 5))
    try storage.saveAttempts(state)
    #expect(try FileVaultStorage(directory: directory).loadAttempts() == state)
  }
}
