import Foundation
import VaultCore

/// Composition root: the only place that picks concrete implementations.
@MainActor
enum AppComposition {
  struct Result {
    let session: SessionModel
    let clipboard: ClipboardService
    let vault: Vault
    let showShield: Bool
  }

  static func make() -> Result {
    var directory = URL.applicationSupportDirectory.appending(
      path: "SecureVault", directoryHint: .isDirectory)
    var iterations = PBKDF2.defaultIterations
    var defaults = UserDefaults.standard
    var showShield = false
    #if DEBUG
      // UI-test hooks. Compiled out of Release builds, so production can never run with a weak KDF.
      let arguments = ProcessInfo.processInfo.arguments
      if arguments.contains("-UITestReset") || arguments.contains("-UITestSeed") {
        directory = FileManager.default.temporaryDirectory.appending(
          path: "securevault-ui-\(UUID().uuidString)")
        iterations = 1_000
        defaults = UserDefaults(suiteName: "securevault-ui-\(UUID().uuidString)") ?? .standard
      }
      showShield = arguments.contains("-UITestShield")
    #endif
    let vault = Vault(storage: FileVaultStorage(directory: directory), kdfIterations: iterations)
    return Result(
      session: SessionModel(vault: vault, biometrics: KeychainBiometricKeyStore(), defaults: defaults),
      clipboard: ClipboardService(), vault: vault, showShield: showShield)
  }
}
