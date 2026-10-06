import Foundation

/// Best-effort wiping of byte buffers we own. `memset_s` is not optimised away, unlike a plain loop.
/// Swift `String`s and `SymmetricKey` storage cannot be wiped; that limit is documented in the threat model.
enum Zeroize {
  static func wipe(_ bytes: inout [UInt8]) {
    bytes.withUnsafeMutableBytes { buffer in
      if let base = buffer.baseAddress { _ = memset_s(base, buffer.count, 0, buffer.count) }
    }
  }
}
