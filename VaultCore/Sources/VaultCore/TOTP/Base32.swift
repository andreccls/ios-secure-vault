import Foundation

/// RFC 4648 base32 decoder, tolerant of what users paste: lowercase, spaces, dashes, padding.
public enum Base32 {
  private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".utf8)
  private static let lookup: [UInt8: UInt8] = Dictionary(
    uniqueKeysWithValues: alphabet.enumerated().map { ($1, UInt8($0)) })

  /// Canonical form (uppercase, no separators/padding), or `nil` when empty or not base32.
  public static func normalize(_ input: String) -> String? {
    let cleaned = input.uppercased().filter { !" -=\t\n".contains($0) }
    guard !cleaned.isEmpty, cleaned.utf8.allSatisfy({ lookup[$0] != nil }) else { return nil }
    return cleaned
  }

  public static func decode(_ input: String) -> Data? {
    guard let canonical = normalize(input) else { return nil }
    var buffer: UInt32 = 0
    var bits = 0
    var output = Data()
    for char in canonical.utf8 {
      buffer = (buffer << 5) | UInt32(lookup[char]!)
      bits += 5
      if bits >= 8 {
        bits -= 8
        output.append(UInt8((buffer >> UInt32(bits)) & 0xFF))
      }
    }
    return output
  }
}
