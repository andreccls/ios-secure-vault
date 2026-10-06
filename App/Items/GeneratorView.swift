import SwiftUI
import VaultCore

struct GeneratorView: View {
  var onUse: ((String) -> Void)?
  @Environment(\.dismiss) private var dismiss
  @Environment(ClipboardService.self) private var clipboard
  @State private var model = GeneratorModel()

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Text(model.generated)
            .font(.system(.title3, design: .monospaced)).textSelection(.enabled)
            .accessibilityIdentifier("generatedPassword")
          StrengthMeter(password: model.generated)
          Button("Gerar outra", systemImage: "arrow.clockwise") { model.regenerate() }
          Button("Copiar", systemImage: "doc.on.doc") { clipboard.copy(model.generated, label: "Senha") }
        }
        Section("Opções") {
          Stepper(value: $model.options.length, in: PasswordGeneratorOptions.lengthRange) {
            Text("Comprimento: \(model.options.length)")
          }
          .accessibilityIdentifier("lengthStepper")
          classToggle("Minúsculas (a–z)", \.lowercase)
          classToggle("Maiúsculas (A–Z)", \.uppercase)
          classToggle("Números (0–9)", \.digits)
          classToggle("Símbolos (!@#…)", \.symbols)
          Toggle("Evitar caracteres ambíguos (I l 1 O 0)", isOn: $model.options.avoidAmbiguous)
          Text("Entropia estimada: ~\(Int(model.entropyBits)) bits").font(.footnote).foregroundStyle(
            .secondary)
        }
      }
      .navigationTitle("Gerador de senha")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } }
        if let onUse {
          ToolbarItem(placement: .confirmationAction) {
            Button("Usar") {
              onUse(model.generated)
              dismiss()
            }
          }
        }
      }
    }
  }

  private func classToggle(_ title: String, _ keyPath: WritableKeyPath<PasswordGeneratorOptions, Bool>)
    -> some View
  {
    Toggle(
      title,
      isOn: Binding(get: { model.options[keyPath: keyPath] }, set: { model.options[keyPath: keyPath] = $0 })
    )
    .disabled(!model.canDisable(keyPath))
  }
}
