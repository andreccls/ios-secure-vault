import SwiftUI
import VaultCore

struct ItemEditorView: View {
  @State var draft: ItemDraft
  let existing: VaultItem?
  @Environment(SessionModel.self) private var session
  @Environment(\.dismiss) private var dismiss
  @State private var error: String?
  @State private var showGenerator = false

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField(titlePrompt, text: $draft.title).accessibilityIdentifier("titleField")
          Toggle("Favorito", isOn: $draft.isFavorite)
        }
        switch draft.kind {
        case .password: passwordFields
        case .authenticator: authenticatorFields
        case .authKey: keyFields
        }
        if let error {
          Text(error).foregroundStyle(.red).accessibilityIdentifier("editorError")
        }
      }
      .textInputAutocapitalization(.never).autocorrectionDisabled()
      .navigationTitle(existing == nil ? "Novo item" : "Editar item")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Salvar", action: save).accessibilityIdentifier("saveButton")
        }
      }
      // Typing in a form is activity even though it produces no touches.
      .onChange(of: draft) { session.recordActivity() }
      .sheet(isPresented: $showGenerator) {
        GeneratorView { draft.password = $0 }
      }
    }
  }

  private var titlePrompt: String { draft.kind == .authKey ? "Rótulo" : "Título" }

  @ViewBuilder private var passwordFields: some View {
    Section {
      TextField("Usuário", text: $draft.username).textContentType(.username).accessibilityIdentifier("usernameField")
      SecureField("Senha", text: $draft.password).accessibilityIdentifier("passwordField")
      StrengthMeter(password: draft.password)
      Button("Gerar senha forte", systemImage: "wand.and.stars") { showGenerator = true }
      TextField("URL", text: $draft.url).keyboardType(.URL)
    }
    Section("Notas") { TextField("Notas", text: $draft.notes, axis: .vertical).textInputAutocapitalization(.sentences) }
  }

  @ViewBuilder private var authenticatorFields: some View {
    Section {
      TextField("Emissor (ex.: Example Corp)", text: $draft.issuer)
      TextField("Conta (ex.: nome@example.com)", text: $draft.account)
      TextField("Segredo base32 ou URI otpauth://", text: $draft.secretInput, axis: .vertical)
        .accessibilityIdentifier("secretField")
    } footer: {
      Text("Cole a URI otpauth:// do QR code ou digite o segredo manualmente. Algoritmo, dígitos e período vêm da URI (padrão: SHA1, 6, 30 s).")
    }
  }

  @ViewBuilder private var keyFields: some View {
    Section {
      Picker("Tipo", selection: $draft.keyKind) {
        ForEach(AuthKeyKind.allCases, id: \.self) { Text($0.title).tag($0) }
      }
      TextField("Valor secreto", text: $draft.secretInput, axis: .vertical)
        .lineLimit(1...8).font(.system(.body, design: .monospaced)).accessibilityIdentifier("secretField")
    }
    Section("Notas") { TextField("Notas", text: $draft.notes, axis: .vertical).textInputAutocapitalization(.sentences) }
  }

  private func save() {
    do {
      let item = try draft.build(
        id: existing?.id ?? UUID(), createdAt: existing?.createdAt ?? Date())
      Task {
        if await session.save(item) { dismiss() } else { error = session.errorMessage }
      }
    } catch {
      self.error = error.localizedDescription
    }
  }
}
