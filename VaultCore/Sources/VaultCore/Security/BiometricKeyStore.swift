import Foundation

public enum BiometricError: Error, Equatable {
  case unavailable
  case cancelled
  case notFound
  case failed
}

/// Port for the biometric-protected copy of the DEK. The real implementation is the Keychain
/// (`KeychainBiometricKeyStore`); tests and previews use fakes.
public protocol BiometricKeyStore: Sendable {
  /// Biometry is enrolled and usable on this device.
  var isAvailable: Bool { get }
  var hasStoredKey: Bool { get }
  func save(key: Data) throws
  /// Prompts Face ID / Touch ID, then returns the stored key.
  func loadKey(reason: String) async throws -> Data
  func deleteKey()
}
