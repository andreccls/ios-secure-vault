import Foundation

public struct PasswordGeneratorOptions: Equatable, Sendable {
  public static let lengthRange = 8...64

  public var length: Int
  public var lowercase: Bool
  public var uppercase: Bool
  public var digits: Bool
  public var symbols: Bool
  public var avoidAmbiguous: Bool

  public init(
    length: Int = 20, lowercase: Bool = true, uppercase: Bool = true, digits: Bool = true,
    symbols: Bool = true, avoidAmbiguous: Bool = false
  ) {
    self.length = length
    self.lowercase = lowercase
    self.uppercase = uppercase
    self.digits = digits
    self.symbols = symbols
    self.avoidAmbiguous = avoidAmbiguous
  }
}

public enum PasswordGeneratorError: Error, Equatable { case noCharacterClass }

/// Uniform random passwords from the system CSPRNG. `Int.random(in:using:)` uses rejection sampling, so there
/// is no modulo bias. At least one character of every selected class is guaranteed, then the result is shuffled.
public enum PasswordGenerator {
  static let ambiguous: Set<Character> = ["I", "l", "1", "O", "0", "o"]
  static let symbols = "!@#$%^&*()-_=+[]{};:,.?"

  private static func classes(for options: PasswordGeneratorOptions) -> [[Character]] {
    var result: [[Character]] = []
    if options.lowercase { result.append(Array("abcdefghijklmnopqrstuvwxyz")) }
    if options.uppercase { result.append(Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")) }
    if options.digits { result.append(Array("0123456789")) }
    if options.symbols { result.append(Array(symbols)) }
    guard options.avoidAmbiguous else { return result }
    return result.map { $0.filter { !ambiguous.contains($0) } }
  }

  public static func generate(_ options: PasswordGeneratorOptions) throws -> String {
    var generator = SystemRandomNumberGenerator()
    return try generate(options, using: &generator)
  }

  public static func generate(
    _ options: PasswordGeneratorOptions, using generator: inout some RandomNumberGenerator
  ) throws -> String {
    let groups = classes(for: options)
    guard !groups.isEmpty else { throw PasswordGeneratorError.noCharacterClass }
    let length = min(
      max(options.length, PasswordGeneratorOptions.lengthRange.lowerBound),
      PasswordGeneratorOptions.lengthRange.upperBound)
    let pool = groups.flatMap { $0 }
    var characters = groups.map { $0.randomElement(using: &generator)! }
    while characters.count < length { characters.append(pool.randomElement(using: &generator)!) }
    characters.shuffle(using: &generator)
    return String(characters)
  }

  /// log2(pool^length): the entropy of a password drawn uniformly with these options.
  public static func entropyBits(_ options: PasswordGeneratorOptions) -> Double {
    let pool = classes(for: options).reduce(0) { $0 + $1.count }
    guard pool > 0 else { return 0 }
    return Double(options.length) * log2(Double(pool))
  }
}
