import Foundation
import Testing

@testable import VaultCore

private let sha1Secret = Data("12345678901234567890".utf8)
private let sha256Secret = Data("12345678901234567890123456789012".utf8)
private let sha512Secret = Data("1234567890123456789012345678901234567890123456789012345678901234".utf8)

@Suite("TOTP RFC 6238 Appendix B vectors (8 digits)")
struct TOTPVectorTests {
  static let vectors: [(Int, String, String, String)] = [
    (59, "94287082", "46119246", "90693936"),
    (1_111_111_109, "07081804", "68084774", "25091201"),
    (1_111_111_111, "14050471", "67062674", "99943326"),
    (1_234_567_890, "89005924", "91819424", "93441116"),
    (2_000_000_000, "69279037", "90698825", "38618901"),
    (20_000_000_000, "65353130", "77737706", "47863826"),
  ]

  @Test(arguments: vectors)
  func officialVectors(time: Int, sha1: String, sha256: String, sha512: String) {
    let date = Date(timeIntervalSince1970: TimeInterval(time))
    #expect(TOTP.code(secret: sha1Secret, at: date, algorithm: .sha1, digits: 8, period: 30) == sha1)
    #expect(TOTP.code(secret: sha256Secret, at: date, algorithm: .sha256, digits: 8, period: 30) == sha256)
    #expect(TOTP.code(secret: sha512Secret, at: date, algorithm: .sha512, digits: 8, period: 30) == sha512)
  }

  @Test func sixDigitCodeIsTheTruncationOfTheEightDigitOne() {
    // 94287082 mod 10^6 = 287082 (RFC 4226 truncation), left-padded.
    let date = Date(timeIntervalSince1970: 59)
    #expect(TOTP.code(secret: sha1Secret, at: date, algorithm: .sha1, digits: 6, period: 30) == "287082")
  }

  @Test func codesArePaddedWithLeadingZeros() {
    // t = 1111111109 yields 07081804 with 8 digits; 6 digits keep the leading zero of "081804".
    let date = Date(timeIntervalSince1970: 1_111_111_109)
    #expect(TOTP.code(secret: sha1Secret, at: date, algorithm: .sha1, digits: 6, period: 30) == "081804")
  }

  @Test func secondsRemainingCountsDownWithinThePeriod() {
    #expect(TOTP.secondsRemaining(at: Date(timeIntervalSince1970: 60), period: 30) == 30)
    #expect(TOTP.secondsRemaining(at: Date(timeIntervalSince1970: 89), period: 30) == 1)
    #expect(TOTP.secondsRemaining(at: Date(timeIntervalSince1970: 59), period: 30) == 1)
  }
}

@Suite("Base32 (RFC 4648)")
struct Base32Tests {
  @Test func decodesRFCVectors() {
    #expect(Base32.decode("MZXW6YTBOI======") == Data("foobar".utf8))
    #expect(Base32.decode("MZXW6YQ=") == Data("foob".utf8))
    #expect(Base32.decode("MY======") == Data("f".utf8))
  }

  @Test func isCaseInsensitiveAndIgnoresSpacesDashesAndPadding() {
    #expect(Base32.decode("gezd gnbv-gy3t qojq gezd gnbv gy3t qojq") == sha1Secret)
  }

  @Test func rejectsInvalidAlphabetAndEmptyInput() {
    #expect(Base32.decode("MZXW6!YT") == nil)
    #expect(Base32.decode("1890") == nil)
    #expect(Base32.decode("   ") == nil)
  }
}

@Suite("otpauth:// parsing")
struct OTPAuthURITests {
  @Test func parsesFullURI() throws {
    let uri =
      "otpauth://totp/Example%20Corp:alice@example.com?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&issuer=Example%20Corp&algorithm=SHA256&digits=8&period=60"
    let content = try AuthenticatorContent(otpauthURI: uri)
    #expect(content.issuer == "Example Corp")
    #expect(content.account == "alice@example.com")
    #expect(content.secret == "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ")
    #expect(content.algorithm == .sha256)
    #expect(content.digits == 8)
    #expect(content.period == 60)
  }

  @Test func appliesDefaultsAndTakesIssuerFromLabel() throws {
    let content = try AuthenticatorContent(
      otpauthURI: "otpauth://totp/Acme:bob?secret=gezdgnbvgy3tqojq")
    #expect(content.issuer == "Acme")
    #expect(content.account == "bob")
    #expect(content.algorithm == .sha1)
    #expect(content.digits == 6)
    #expect(content.period == 30)
    #expect(content.secret == "GEZDGNBVGY3TQOJQ")
  }

  @Test func labelWithoutIssuerLeavesItEmpty() throws {
    let content = try AuthenticatorContent(otpauthURI: "otpauth://totp/solo?secret=GEZDGNBV")
    #expect(content.issuer == "")
    #expect(content.account == "solo")
  }

  @Test(arguments: [
    "https://example.com/?secret=GEZDGNBV",
    "otpauth://hotp/x?secret=GEZDGNBV&counter=1",
    "otpauth://totp/x",
    "otpauth://totp/x?secret=!!!",
    "otpauth://totp/x?secret=GEZDGNBV&digits=4",
    "otpauth://totp/x?secret=GEZDGNBV&digits=9",
    "otpauth://totp/x?secret=GEZDGNBV&period=0",
    "otpauth://totp/x?secret=GEZDGNBV&algorithm=MD5",
    "not a uri at all",
  ])
  func rejectsInvalid(uri: String) {
    #expect(throws: OTPError.self) { try AuthenticatorContent(otpauthURI: uri) }
  }

  @Test func manualEntryValidatesSecretAndNormalizesIt() throws {
    let content = try AuthenticatorContent(issuer: "X", account: "y", secretInput: "gezd gnbv")
    #expect(content.secret == "GEZDGNBV")
    #expect(throws: OTPError.invalidSecret) {
      try AuthenticatorContent(issuer: "X", account: "y", secretInput: "not base32 !")
    }
  }

  @Test func currentCodeUsesTheStoredSecret() throws {
    let content = try AuthenticatorContent(
      issuer: "X", account: "y", secretInput: "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ", digits: 8)
    #expect(content.code(at: Date(timeIntervalSince1970: 59)) == "94287082")
    #expect(content.secondsRemaining(at: Date(timeIntervalSince1970: 59)) == 1)
  }
}
