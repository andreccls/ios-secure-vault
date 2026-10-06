import CryptoKit
import Foundation

public enum OTPAlgorithm: String, Codable, CaseIterable, Sendable {
  case sha1 = "SHA1"
  case sha256 = "SHA256"
  case sha512 = "SHA512"
}

/// RFC 6238 (TOTP) on top of RFC 4226 (HOTP dynamic truncation).
public enum TOTP {
  public static func code(
    secret: Data, at date: Date, algorithm: OTPAlgorithm = .sha1, digits: Int = 6, period: Int = 30
  ) -> String {
    let counter = UInt64(max(0, date.timeIntervalSince1970)) / UInt64(period)
    let message = withUnsafeBytes(of: counter.bigEndian) { Data($0) }
    let key = SymmetricKey(data: secret)
    let mac: [UInt8]
    switch algorithm {
    case .sha1: mac = Array(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: key))
    case .sha256: mac = Array(HMAC<SHA256>.authenticationCode(for: message, using: key))
    case .sha512: mac = Array(HMAC<SHA512>.authenticationCode(for: message, using: key))
    }
    let offset = Int(mac[mac.count - 1] & 0x0F)
    let truncated =
      (UInt32(mac[offset] & 0x7F) << 24) | (UInt32(mac[offset + 1]) << 16)
      | (UInt32(mac[offset + 2]) << 8) | UInt32(mac[offset + 3])
    var modulus: UInt32 = 1
    for _ in 0..<digits { modulus *= 10 }
    let value = String(truncated % modulus)
    return String(repeating: "0", count: digits - value.count) + value
  }

  /// Seconds until the current code changes (1...period).
  public static func secondsRemaining(at date: Date, period: Int = 30) -> Int {
    period - Int(max(0, date.timeIntervalSince1970)) % period
  }
}
