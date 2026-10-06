#if DEBUG
  import Foundation
  import VaultCore

  /// Fictional data for UI tests and README screenshots (`-UITestSeed`). Every value is an obvious placeholder;
  /// the TOTP secret is the RFC 6238 test secret.
  enum DemoData {
    static let masterPassword = "example-master-password"

    static func seedIfRequested(_ vault: Vault) async {
      guard ProcessInfo.processInfo.arguments.contains("-UITestSeed") else { return }
      try? await vault.create(masterPassword: masterPassword)
      let totp = { (issuer: String, account: String) in
        try! AuthenticatorContent(
          issuer: issuer, account: account, secretInput: "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ")
      }
      let items: [VaultItem] = [
        VaultItem(
          title: "Example Mail", isFavorite: true,
          content: .password(
            PasswordContent(
              username: "alice@example.com", password: "Not-A-Real-Password-1!", url: "https://mail.example.com",
              notes: "Conta fictícia de demonstração."))),
        VaultItem(
          title: "Example Bank",
          content: .password(
            PasswordContent(username: "alice", password: "Fake-Pass-Example-2", url: "https://bank.example.com"))),
        VaultItem(title: "Example Corp", content: .authenticator(totp("Example Corp", "alice@example.com"))),
        VaultItem(title: "Example Git", content: .authenticator(totp("Example Git", "alice"))),
        VaultItem(
          title: "Chave de API (pagamentos)", isFavorite: true,
          content: .authKey(AuthKeyContent(keyKind: .apiKey, secret: "sk_test_EXAMPLE_not_a_real_key_0000", notes: "Somente sandbox."))),
        VaultItem(
          title: "Servidor de build",
          content: .authKey(AuthKeyContent(keyKind: .sshKey, secret: "-----BEGIN EXAMPLE KEY-----\nNOT-A-REAL-KEY\n-----END EXAMPLE KEY-----"))),
        VaultItem(
          title: "Recuperação do e-mail",
          content: .authKey(AuthKeyContent(keyKind: .recoveryCodes, secret: "EXAMPLE-0001\nEXAMPLE-0002\nEXAMPLE-0003"))),
      ]
      for item in items { try? await vault.save(item) }
      await vault.lock()
    }
  }
#endif
