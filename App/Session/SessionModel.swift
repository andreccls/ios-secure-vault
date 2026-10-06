import Foundation
import Observation
import VaultCore

/// Presentation state for the whole app: lock phase, decrypted items (memory only), settings, auto-lock.
/// Depends on ports (`Vault`, `BiometricKeyStore`) so it is testable with in-memory fakes.
@MainActor @Observable
final class SessionModel {
  enum Phase: Equatable { case loading, setup, locked, unlocked }

  private(set) var phase: Phase = .loading
  private(set) var items: [VaultItem] = []
  private(set) var biometricsEnabled: Bool
  var errorMessage: String?
  var autoLockTimeout: AutoLockTimeout {
    didSet {
      defaults.set(autoLockTimeout.rawValue, forKey: Keys.timeout)
      monitor.timeout = autoLockTimeout
    }
  }

  var biometricsAvailable: Bool { biometrics.isAvailable }

  @ObservationIgnored private let vault: Vault
  @ObservationIgnored private let biometrics: BiometricKeyStore
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let now: @Sendable () -> Date
  @ObservationIgnored private var monitor: InactivityMonitor
  @ObservationIgnored private var lockTask: Task<Void, Never>?

  private enum Keys {
    static let timeout = "autoLockTimeout"
    static let biometrics = "biometricsEnabled"
  }

  init(
    vault: Vault, biometrics: BiometricKeyStore, defaults: UserDefaults = .standard,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.vault = vault
    self.biometrics = biometrics
    self.defaults = defaults
    self.now = now
    let timeout = AutoLockTimeout(rawValue: defaults.integer(forKey: Keys.timeout)) ?? .oneMinute
    self.autoLockTimeout = timeout
    self.monitor = InactivityMonitor(timeout: timeout, now: now())
    self.biometricsEnabled = defaults.bool(forKey: Keys.biometrics)
  }

  // MARK: Lock state

  func bootstrap() async {
    do {
      phase = try await vault.isInitialized() ? .locked : .setup
    } catch {
      errorMessage = Self.message(for: error)
      phase = .setup
    }
  }

  @discardableResult
  func createVault(password: String, confirmation: String) async -> Bool {
    guard password == confirmation else {
      errorMessage = "As senhas não coincidem."
      return false
    }
    return await perform {
      try await self.vault.create(masterPassword: password)
      self.items = []
      self.didUnlock()
    }
  }

  @discardableResult
  func unlock(password: String) async -> Bool {
    await lockTask?.value
    return await perform {
      try await self.vault.unlock(masterPassword: password)
      self.items = try await self.vault.items()
      self.didUnlock()
    }
  }

  func unlockWithBiometrics() async {
    guard biometricsEnabled, phase == .locked else { return }
    await lockTask?.value
    do {
      let key = try await biometrics.loadKey(reason: "Desbloquear o cofre")
      try await vault.unlock(key: key)
      items = try await vault.items()
      didUnlock()
    } catch BiometricError.cancelled {
      return
    } catch {
      // Biometry set changed, keychain item gone, or stale key: fall back to the master password.
      disableBiometrics()
      errorMessage = "A biometria não pôde desbloquear o cofre. Use a senha mestra."
    }
  }

  func lock() {
    guard phase == .unlocked else { return }
    phase = .locked
    items = []
    errorMessage = nil
    lockTask = Task { await vault.lock() }
  }

  /// Called when the scene reaches `.background`: no grace period.
  func handleBackground() { lock() }

  func recordActivity() { monitor.recordActivity(at: now()) }

  func checkInactivity() {
    if phase == .unlocked, monitor.isExpired(at: now()) { lock() }
  }

  private func didUnlock() {
    errorMessage = nil
    monitor = InactivityMonitor(timeout: autoLockTimeout, now: now())
    phase = .unlocked
  }

  // MARK: Items

  func save(_ item: VaultItem) async -> Bool {
    await perform {
      try await self.vault.save(item)
      if let index = self.items.firstIndex(where: { $0.id == item.id }) {
        self.items[index] = item
      } else {
        self.items.append(item)
      }
    }
  }

  func delete(id: UUID) async {
    await perform {
      try await self.vault.delete(id: id)
      self.items.removeAll { $0.id == id }
    }
  }

  func toggleFavorite(_ item: VaultItem) async {
    var updated = item
    updated.isFavorite.toggle()
    updated.updatedAt = now()
    _ = await save(updated)
  }

  func item(id: UUID) -> VaultItem? { items.first { $0.id == id } }

  // MARK: Settings

  func enableBiometrics() async {
    guard biometrics.isAvailable else {
      errorMessage = "Face ID/Touch ID não está disponível neste aparelho."
      return
    }
    await perform {
      try self.biometrics.save(key: try await self.vault.exportKey())
      self.biometricsEnabled = true
      self.defaults.set(true, forKey: Keys.biometrics)
    }
  }

  func disableBiometrics() {
    biometrics.deleteKey()
    biometricsEnabled = false
    defaults.set(false, forKey: Keys.biometrics)
  }

  @discardableResult
  func changeMasterPassword(current: String, new: String, confirmation: String) async -> Bool {
    guard new == confirmation else {
      errorMessage = "As senhas não coincidem."
      return false
    }
    return await perform { try await self.vault.changeMasterPassword(current: current, new: new) }
  }

  func exportBackup(password: String) async -> Data? {
    var result: Data?
    await perform { result = try BackupService.export(items: self.items, password: password) }
    return result
  }

  func importBackup(_ data: Data, password: String) async -> Int? {
    var count: Int?
    await perform {
      count = try await self.vault.importItems(try BackupService.open(data, password: password))
      self.items = try await self.vault.items()
    }
    return count
  }

  // MARK: Errors

  @discardableResult
  private func perform(_ work: () async throws -> Void) async -> Bool {
    do {
      try await work()
      return true
    } catch {
      errorMessage = Self.message(for: error)
      return false
    }
  }

  static func message(for error: Error) -> String {
    switch error as? VaultError {
    case .wrongPassword: "Senha incorreta."
    case .weakPassword: "Use pelo menos \(Vault.minimumPasswordLength) caracteres."
    case .throttled(let seconds): "Muitas tentativas. Aguarde \(Int(seconds.rounded(.up))) s."
    case .corruptedRecord: "Dados corrompidos ou adulterados."
    case .locked: "O cofre está bloqueado."
    case .alreadyInitialized: "O cofre já foi criado."
    case .notInitialized: "O cofre ainda não foi criado."
    case nil: "Não foi possível concluir a operação."
    }
  }
}
