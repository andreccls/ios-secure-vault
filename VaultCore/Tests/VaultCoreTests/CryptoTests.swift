import CryptoKit
import Foundation
import Testing

@testable import VaultCore

private func hex(_ key: SymmetricKey) -> String {
  key.withUnsafeBytes { $0.map { String(format: "%02x", $0) }.joined() }
}

@Suite("PBKDF2-HMAC-SHA256")
struct KeyDerivationTests {
  // Known-answer vectors for PBKDF2-HMAC-SHA256, dkLen = 32 (password "password", salt "salt").
  @Test(arguments: [
    (1, "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b"),
    (2, "ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43"),
    (4096, "c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a"),
  ])
  func knownVectors(iterations: Int, expected: String) throws {
    let key = try PBKDF2.deriveKey(
      password: "password", salt: Data("salt".utf8), iterations: iterations)
    #expect(hex(key) == expected)
  }

  @Test func deterministicForSameInputs() throws {
    let salt = Data(repeating: 7, count: 16)
    let a = try PBKDF2.deriveKey(password: "correct horse", salt: salt, iterations: 1000)
    let b = try PBKDF2.deriveKey(password: "correct horse", salt: salt, iterations: 1000)
    #expect(hex(a) == hex(b))
  }

  @Test func differsWithSaltPasswordAndIterations() throws {
    let salt = Data(repeating: 7, count: 16)
    let base = hex(try PBKDF2.deriveKey(password: "pw-12345", salt: salt, iterations: 1000))
    #expect(base != hex(try PBKDF2.deriveKey(password: "pw-12346", salt: salt, iterations: 1000)))
    #expect(
      base
        != hex(
          try PBKDF2.deriveKey(password: "pw-12345", salt: Data(repeating: 8, count: 16), iterations: 1000)))
    #expect(base != hex(try PBKDF2.deriveKey(password: "pw-12345", salt: salt, iterations: 1001)))
  }

  @Test func unicodeIsNormalizedSoComposedAndDecomposedMatch() throws {
    let salt = Data(repeating: 1, count: 16)
    let composed = try PBKDF2.deriveKey(password: "caf\u{00E9}-senha", salt: salt, iterations: 10)
    let decomposed = try PBKDF2.deriveKey(password: "cafe\u{0301}-senha", salt: salt, iterations: 10)
    #expect(hex(composed) == hex(decomposed))
  }

  @Test func rejectsInvalidParameters() {
    #expect(throws: KeyDerivationError.invalidParameters) {
      try PBKDF2.deriveKey(password: "", salt: Data(repeating: 1, count: 16), iterations: 10)
    }
    #expect(throws: KeyDerivationError.invalidParameters) {
      try PBKDF2.deriveKey(password: "x", salt: Data(), iterations: 10)
    }
    #expect(throws: KeyDerivationError.invalidParameters) {
      try PBKDF2.deriveKey(password: "x", salt: Data(repeating: 1, count: 16), iterations: 0)
    }
  }

  @Test func randomSaltHasExpectedSizeAndIsNotRepeated() {
    let salts = Set((0..<50).map { _ in PBKDF2.randomSalt() })
    #expect(salts.count == 50)
    #expect(salts.allSatisfy { $0.count == PBKDF2.saltLength })
  }
}

@Suite("AES-GCM cipher")
struct CipherTests {
  let key = SymmetricKey(size: .bits256)
  let aad = Data("item-1".utf8)

  @Test func roundTrip() throws {
    let plaintext = Data("segredo de teste".utf8)
    let sealed = try AESGCMCipher.seal(plaintext, key: key, aad: aad)
    #expect(sealed != plaintext)
    #expect(try AESGCMCipher.open(sealed, key: key, aad: aad) == plaintext)
  }

  @Test func emptyPlaintextRoundTrips() throws {
    let sealed = try AESGCMCipher.seal(Data(), key: key, aad: aad)
    #expect(try AESGCMCipher.open(sealed, key: key, aad: aad).isEmpty)
  }

  @Test func tamperedCiphertextIsRejectedAtEveryPosition() throws {
    let sealed = try AESGCMCipher.seal(Data("abcdef".utf8), key: key, aad: aad)
    for index in sealed.indices {
      var corrupted = sealed
      corrupted[index] ^= 0x01
      #expect(throws: CipherError.authenticationFailed) {
        try AESGCMCipher.open(corrupted, key: key, aad: aad)
      }
    }
  }

  @Test func wrongAADIsRejected() throws {
    let sealed = try AESGCMCipher.seal(Data("x".utf8), key: key, aad: aad)
    #expect(throws: CipherError.authenticationFailed) {
      try AESGCMCipher.open(sealed, key: key, aad: Data("item-2".utf8))
    }
  }

  @Test func wrongKeyIsRejected() throws {
    let sealed = try AESGCMCipher.seal(Data("x".utf8), key: key, aad: aad)
    #expect(throws: CipherError.authenticationFailed) {
      try AESGCMCipher.open(sealed, key: SymmetricKey(size: .bits256), aad: aad)
    }
  }

  @Test func truncatedInputIsMalformed() {
    #expect(throws: CipherError.malformedCiphertext) {
      try AESGCMCipher.open(Data(repeating: 0, count: 5), key: key, aad: aad)
    }
  }

  @Test func nonceIsNeverRepeatedForTheSamePlaintext() throws {
    let plaintext = Data("same".utf8)
    var nonces = Set<Data>()
    for _ in 0..<5000 {
      let sealed = try AESGCMCipher.seal(plaintext, key: key, aad: aad)
      nonces.insert(sealed.prefix(AESGCMCipher.nonceLength))
    }
    #expect(nonces.count == 5000)
  }
}
