import Foundation

/// A deliberately simple heuristic for the strength meter (not zxcvbn): pool size x unique characters, plus a
/// tiny blocklist. It over-estimates human-chosen passwords with patterns; see THREAT_MODEL.md.
public enum PasswordStrength {
  public enum Level: Int, Comparable, Sendable {
    case veryWeak, weak, fair, good, strong
    public static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
  }

  public struct Result: Equatable, Sendable {
    public let bits: Double
    public let level: Level
  }

  private static let common: Set<String> = [
    "password", "qwerty", "qwertyuiop", "letmein", "welcome", "admin", "iloveyou", "abc", "senha", "mudar",
  ]

  public static func evaluate(_ password: String) -> Result {
    let stripped = password.lowercased().trimmingCharacters(in: .decimalDigits)
    if password.isEmpty || common.contains(stripped) || Int(password) != nil {
      return Result(bits: 0, level: .veryWeak)
    }
    var pool = 0
    if password.contains(where: \.isLowercase) { pool += 26 }
    if password.contains(where: \.isUppercase) { pool += 26 }
    if password.contains(where: \.isNumber) { pool += 10 }
    if password.contains(where: { !$0.isLetter && !$0.isNumber }) { pool += 33 }
    let bits = Double(Set(password).count) * log2(Double(max(pool, 2)))
    let level: Level =
      switch bits {
      case ..<28: .veryWeak
      case ..<45: .weak
      case ..<60: .fair
      case ..<80: .good
      default: .strong
      }
    return Result(bits: bits, level: level)
  }
}
