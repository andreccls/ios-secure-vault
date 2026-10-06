import CommonCrypto
import CryptoKit
import Foundation

public enum KeyDerivationError: Error, Equatable {
  case invalidParameters
  case derivationFailed(Int32)
}

/// PBKDF2-HMAC-SHA256 through CommonCrypto (hardware-accelerated, no third-party code). See ADR 0003.
public enum PBKDF2 {
  /// OWASP Password Storage Cheat Sheet (2023) recommendation for PBKDF2-HMAC-SHA256.
  public static let defaultIterations = 600_000
  public static let saltLength = 16
  public static let keyLength = 32

  public static func deriveKey(password: String, salt: Data, iterations: Int) throws -> SymmetricKey {
    // NFKC so that "é" typed composed or decomposed (keyboards, copy/paste) yields the same key.
    var passwordBytes = Array(password.precomposedStringWithCompatibilityMapping.utf8)
    defer { Zeroize.wipe(&passwordBytes) }
    guard !passwordBytes.isEmpty, !salt.isEmpty, iterations > 0, iterations <= Int(UInt32.max) else {
      throw KeyDerivationError.invalidParameters
    }
    var derived = [UInt8](repeating: 0, count: keyLength)
    defer { Zeroize.wipe(&derived) }
    let saltBytes = [UInt8](salt)
    let status = passwordBytes.withUnsafeBufferPointer { pwd in
      pwd.withMemoryRebound(to: Int8.self) { pwdChars in
        CCKeyDerivationPBKDF(
          CCPBKDFAlgorithm(kCCPBKDF2), pwdChars.baseAddress, pwdChars.count,
          saltBytes, saltBytes.count,
          CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations),
          &derived, derived.count)
      }
    }
    guard status == kCCSuccess else { throw KeyDerivationError.derivationFailed(status) }
    return SymmetricKey(data: derived)
  }

  public static func randomSalt() -> Data {
    var generator = SystemRandomNumberGenerator()
    return Data((0..<saltLength).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
  }
}
