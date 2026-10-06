import Foundation

public enum OTPError: Error, Equatable {
  case invalidURI
  case unsupportedType
  case invalidSecret
  case invalidParameter(String)
}

public struct AuthenticatorContent: Codable, Hashable, Sendable {
  public var issuer: String
  public var account: String
  /// Canonical base32 (uppercase, no spaces/padding).
  public private(set) var secret: String
  public var algorithm: OTPAlgorithm
  public var digits: Int
  public var period: Int

  /// Manual entry: `secretInput` may be lowercase/spaced; it is validated and normalized.
  public init(
    issuer: String, account: String, secretInput: String, algorithm: OTPAlgorithm = .sha1,
    digits: Int = 6, period: Int = 30
  ) throws {
    guard let normalized = Base32.normalize(secretInput), Base32.decode(normalized) != nil else {
      throw OTPError.invalidSecret
    }
    guard (6...8).contains(digits) else { throw OTPError.invalidParameter("digits") }
    guard (1...300).contains(period) else { throw OTPError.invalidParameter("period") }
    self.issuer = issuer
    self.account = account
    self.secret = normalized
    self.algorithm = algorithm
    self.digits = digits
    self.period = period
  }

  /// Parses `otpauth://totp/Issuer:account?secret=...&issuer=...&algorithm=...&digits=...&period=...`.
  public init(otpauthURI: String) throws {
    guard let components = URLComponents(string: otpauthURI.trimmingCharacters(in: .whitespacesAndNewlines)),
      components.scheme?.lowercased() == "otpauth"
    else { throw OTPError.invalidURI }
    guard components.host?.lowercased() == "totp" else { throw OTPError.unsupportedType }
    let params = Dictionary(
      (components.queryItems ?? []).compactMap { item in item.value.map { (item.name.lowercased(), $0) } },
      uniquingKeysWith: { first, _ in first })
    guard let secret = params["secret"] else { throw OTPError.invalidSecret }

    let label = String(components.path.dropFirst())  // URLComponents already percent-decodes `path`
    let parts = label.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
    let labelIssuer = parts.count == 2 ? parts[0] : ""
    let account = parts.last ?? ""

    var algorithm = OTPAlgorithm.sha1
    if let raw = params["algorithm"] {
      guard let parsed = OTPAlgorithm(rawValue: raw.uppercased()) else {
        throw OTPError.invalidParameter("algorithm")
      }
      algorithm = parsed
    }
    try self.init(
      issuer: params["issuer"] ?? labelIssuer, account: account, secretInput: secret,
      algorithm: algorithm, digits: try Self.intParam(params["digits"], default: 6, name: "digits"),
      period: try Self.intParam(params["period"], default: 30, name: "period"))
  }

  private static func intParam(_ raw: String?, default fallback: Int, name: String) throws -> Int {
    guard let raw else { return fallback }
    guard let value = Int(raw) else { throw OTPError.invalidParameter(name) }
    return value
  }

  public func code(at date: Date) -> String {
    // The secret was validated on init, so decoding cannot fail.
    TOTP.code(
      secret: Base32.decode(secret) ?? Data(), at: date, algorithm: algorithm, digits: digits, period: period)
  }

  public func secondsRemaining(at date: Date) -> Int {
    TOTP.secondsRemaining(at: date, period: period)
  }
}
