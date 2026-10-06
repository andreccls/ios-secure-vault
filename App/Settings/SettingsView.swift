import SwiftUI
import UniformTypeIdentifiers
import VaultCore

struct BackupDocument: FileDocument {
  static let readableContentTypes: [UTType] = [.json]
  var data: Data

  init(data: Data) { self.data = data }
  init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: data)
  }
}

struct SettingsView: View {
  @Environment(SessionModel.self) private var session
  @State private var showChangePassword = false
  @State private var exportPasswordPrompt = false
  @State private var backupPassword = ""
  @State private var exportDocument: BackupDocument?
  @State private var showImporter = false
  @State private var importedData: Data?
  @State private var info: String?

  var body: some View {
    @Bindable var session = session
    NavigationStack {
      Form {
        Section("Segurança") {
          Picker("Bloqueio por inatividade", selection: $session.autoLockTimeout) {
            ForEach(AutoLockTimeout.allCases, id: \.self) { Text(Self.label($0)).tag($0) }
          }
          Toggle(
            "Desbloquear com Face ID / Touch ID",
            isOn: Binding(
              get: { session.biometricsEnabled },
              set: { on in
                if on { Task { await session.enableBiometrics() } } else { session.disableBiometrics() }
              })
          )
          .disabled(!session.biometricsAvailable && !session.biometricsEnabled)
          if !session.biometricsAvailable {
            Text("Biometria indisponível neste aparelho/simulador.").font(.footnote).foregroundStyle(
              .secondary)
          }
          Button("Alterar senha mestra") { showChangePassword = true }
          Button("Bloquear agora", systemImage: "lock.fill") { session.lock() }
            .accessibilityIdentifier("lockNow")
        }
        Section {
          Button("Exportar backup criptografado") { exportPasswordPrompt = true }
          Button("Importar backup") { showImporter = true }
        } header: {
          Text("Backup")
        } footer: {
          Text(
            "O arquivo é cifrado com uma senha própria (PBKDF2 + AES-GCM). Guarde-a: sem ela o backup não abre."
          )
        }
        if let message = session.errorMessage ?? info {
          Section { Text(message).accessibilityIdentifier("settingsMessage") }
        }
        Section("Sobre") {
          DisclaimerBanner()
          LabeledContent("Itens no cofre", value: "\(session.items.count)")
          LabeledContent("Área de transferência", value: "apagada em \(Int(ClipboardService.expiry)) s")
        }
      }
      .navigationTitle("Ajustes")
      .sheet(isPresented: $showChangePassword) { ChangePasswordView() }
      .alert("Senha do backup", isPresented: $exportPasswordPrompt) {
        SecureField("Senha do backup", text: $backupPassword)
        Button("Cancelar", role: .cancel) { backupPassword = "" }
        Button("Exportar") { runExport() }
      } message: {
        Text("Mínimo de \(Vault.minimumPasswordLength) caracteres.")
      }
      .alert(
        "Senha do backup",
        isPresented: Binding(get: { importedData != nil }, set: { if !$0 { importedData = nil } })
      ) {
        SecureField("Senha do backup", text: $backupPassword)
        Button("Cancelar", role: .cancel) {
          backupPassword = ""; importedData = nil
        }
        Button("Importar") { runImport() }
      }
      .fileExporter(
        isPresented: Binding(get: { exportDocument != nil }, set: { if !$0 { exportDocument = nil } }),
        document: exportDocument, contentType: .json, defaultFilename: "secure-vault-backup"
      ) { result in
        if case .failure = result {
          info = "Não foi possível salvar o arquivo."
        } else {
          info = "Backup exportado."
        }
      }
      .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
        guard let url = try? result.get(), url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        importedData = try? Data(contentsOf: url)
      }
    }
  }

  private func runExport() {
    let password = backupPassword
    backupPassword = ""
    Task {
      session.errorMessage = nil
      if let data = await session.exportBackup(password: password) {
        exportDocument = BackupDocument(data: data)
      }
    }
  }

  private func runImport() {
    let password = backupPassword
    backupPassword = ""
    guard let data = importedData else { return }
    importedData = nil
    Task {
      session.errorMessage = nil
      if let count = await session.importBackup(data, password: password) {
        info = "\(count) itens importados."
      }
    }
  }

  private static func label(_ timeout: AutoLockTimeout) -> String {
    switch timeout {
    case .thirtySeconds: "30 segundos"
    case .oneMinute: "1 minuto"
    case .fiveMinutes: "5 minutos"
    case .fifteenMinutes: "15 minutos"
    }
  }
}

struct ChangePasswordView: View {
  @Environment(SessionModel.self) private var session
  @Environment(\.dismiss) private var dismiss
  @State private var current = ""
  @State private var new = ""
  @State private var confirmation = ""

  var body: some View {
    NavigationStack {
      Form {
        Section {
          SecureField("Senha mestra atual", text: $current)
          SecureField("Nova senha mestra", text: $new)
          SecureField("Confirmar nova senha", text: $confirmation)
          StrengthMeter(password: new)
        } footer: {
          Text("Só a chave que protege a chave de dados é recriada; seus itens não são recifrados.")
        }
        if let error = session.errorMessage { Text(error).foregroundStyle(.red) }
      }
      .textInputAutocapitalization(.never).autocorrectionDisabled()
      .navigationTitle("Alterar senha mestra")
      .navigationBarTitleDisplayMode(.inline)
      .onAppear { session.errorMessage = nil }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Alterar") {
            Task {
              if await session.changeMasterPassword(current: current, new: new, confirmation: confirmation) {
                dismiss()
              }
            }
          }
          .disabled(current.isEmpty || new.isEmpty)
        }
      }
    }
  }
}
