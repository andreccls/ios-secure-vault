import SwiftUI
import VaultCore

struct UnlockView: View {
  let isSetup: Bool
  @Environment(SessionModel.self) private var session
  @State private var password = ""
  @State private var confirmation = ""
  @State private var isWorking = false
  @FocusState private var focused: Bool

  private var canSubmit: Bool {
    !password.isEmpty && (!isSetup || !confirmation.isEmpty) && !isWorking
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 20) {
        Image(systemName: isSetup ? "lock.shield" : "lock.fill")
          .font(.system(size: 56)).foregroundStyle(.tint).accessibilityHidden(true)
        Text(isSetup ? "Criar cofre" : "Cofre bloqueado").font(.largeTitle.bold())
        DisclaimerBanner()
        VStack(spacing: 12) {
          SecureField("Senha mestra", text: $password)
            .textFieldStyle(.roundedBorder).focused($focused)
            .accessibilityIdentifier("masterPassword")
            .onSubmit(submit)
          if isSetup {
            SecureField("Confirmar senha mestra", text: $confirmation)
              .textFieldStyle(.roundedBorder).accessibilityIdentifier("confirmPassword")
              .onSubmit(submit)
            StrengthMeter(password: password)
            Text("Mínimo de \(Vault.minimumPasswordLength) caracteres. Não há recuperação: se esquecer a senha mestra, os dados são irrecuperáveis.")
              .font(.footnote).foregroundStyle(.secondary)
          }
        }
        .textInputAutocapitalization(.never).autocorrectionDisabled()
        if let error = session.errorMessage {
          Text(error).font(.callout).foregroundStyle(.red).accessibilityIdentifier("errorMessage")
        }
        Button(action: submit) {
          Text(isSetup ? "Criar cofre" : "Desbloquear").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent).controlSize(.large).disabled(!canSubmit)
        .accessibilityIdentifier("unlockButton")
        if !isSetup, session.biometricsEnabled {
          Button {
            Task { await session.unlockWithBiometrics() }
          } label: {
            Label("Usar Face ID / Touch ID", systemImage: "faceid").frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered).controlSize(.large)
        }
      }
      .padding()
      .frame(maxWidth: 480)
    }
    .scrollDismissesKeyboard(.interactively)
    .task {
      if !isSetup { await session.unlockWithBiometrics() }
    }
  }

  private func submit() {
    guard canSubmit else { return }
    isWorking = true
    Task {
      if isSetup {
        await session.createVault(password: password, confirmation: confirmation)
      } else {
        await session.unlock(password: password)
      }
      isWorking = false
      password = ""
      confirmation = ""
    }
  }
}

struct DisclaimerBanner: View {
  var body: some View {
    Label {
      Text("Projeto de exemplo, não auditado. Não guarde segredos reais.").font(.footnote)
    } icon: {
      Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
  }
}

struct StrengthMeter: View {
  let password: String

  private var result: PasswordStrength.Result { PasswordStrength.evaluate(password) }

  private var title: String {
    switch result.level {
    case .veryWeak: "Muito fraca"
    case .weak: "Fraca"
    case .fair: "Razoável"
    case .good: "Boa"
    case .strong: "Forte"
    }
  }

  private var color: Color {
    switch result.level {
    case .veryWeak, .weak: .red
    case .fair: .orange
    case .good: .yellow
    case .strong: .green
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 4) {
        ForEach(0..<5) { index in
          Capsule().fill(index <= result.level.rawValue && !password.isEmpty ? color : Color.secondary.opacity(0.25))
            .frame(height: 6)
        }
      }
      Text(password.isEmpty ? " " : "Força: \(title) (~\(Int(result.bits)) bits)")
        .font(.caption).foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Força da senha")
    .accessibilityValue(password.isEmpty ? "vazia" : title)
  }
}
