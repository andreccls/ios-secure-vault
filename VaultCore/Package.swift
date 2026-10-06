// swift-tools-version: 6.0
import PackageDescription

// Business logic only: domain, crypto, TOTP, persistence. No SwiftUI/UIKit — the module graph enforces
// the dependency rule (App -> VaultCore), see docs/adr/0002.
let package = Package(
  name: "VaultCore",
  platforms: [.iOS(.v17), .macOS(.v14)],
  products: [.library(name: "VaultCore", targets: ["VaultCore"])],
  targets: [
    .target(name: "VaultCore"),
    .testTarget(name: "VaultCoreTests", dependencies: ["VaultCore"]),
  ],
  swiftLanguageModes: [.v6]
)
