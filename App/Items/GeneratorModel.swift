import Observation
import VaultCore

@MainActor @Observable
final class GeneratorModel {
  var options = PasswordGeneratorOptions() {
    didSet { if options != oldValue { regenerate() } }
  }
  private(set) var generated = ""

  var strength: PasswordStrength.Result { PasswordStrength.evaluate(generated) }
  var entropyBits: Double { PasswordGenerator.entropyBits(options) }

  init() { regenerate() }

  func regenerate() {
    // The UI never lets the last character class be switched off, so this only fails for impossible states.
    generated = (try? PasswordGenerator.generate(options)) ?? generated
  }

  /// A class may be turned off only if another one stays on.
  func canDisable(_ keyPath: KeyPath<PasswordGeneratorOptions, Bool>) -> Bool {
    let enabled = [\PasswordGeneratorOptions.lowercase, \.uppercase, \.digits, \.symbols].filter {
      options[keyPath: $0]
    }
    return !(enabled.count == 1 && options[keyPath: keyPath])
  }
}
