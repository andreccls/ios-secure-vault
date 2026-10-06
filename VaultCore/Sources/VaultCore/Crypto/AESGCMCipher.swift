import CryptoKit
import Foundation

public enum CipherError: Error, Equatable {
  case malformedCiphertext
  case authenticationFailed
}

/// AES-256-GCM. Output layout: nonce (12) || ciphertext || tag (16). A fresh random 96-bit nonce is drawn for
/// every `seal` call (CryptoKit default), so one key must not exceed ~2^32 messages (NIST SP 800-38D) — far
/// beyond a personal vault. `aad` is authenticated but not encrypted: it binds a blob to its context.
public enum AESGCMCipher {
  public static let nonceLength = 12

  public static func seal(_ plaintext: Data, key: SymmetricKey, aad: Data) throws -> Data {
    let box = try AES.GCM.seal(plaintext, using: key, authenticating: aad)
    return box.combined!  // always non-nil with CryptoKit's 12-byte nonce
  }

  public static func open(_ combined: Data, key: SymmetricKey, aad: Data) throws -> Data {
    guard let box = try? AES.GCM.SealedBox(combined: combined) else {
      throw CipherError.malformedCiphertext
    }
    do {
      return try AES.GCM.open(box, using: key, authenticating: aad)
    } catch {
      throw CipherError.authenticationFailed
    }
  }
}
