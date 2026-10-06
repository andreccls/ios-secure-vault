import VaultCore

extension ItemKind {
  var title: String {
    switch self {
    case .password: "Senhas"
    case .authenticator: "Autenticadores"
    case .authKey: "Chaves"
    }
  }

  var singular: String {
    switch self {
    case .password: "senha"
    case .authenticator: "autenticador"
    case .authKey: "chave"
    }
  }

  var icon: String {
    switch self {
    case .password: "key.fill"
    case .authenticator: "number.circle.fill"
    case .authKey: "terminal.fill"
    }
  }
}

extension AuthKeyKind {
  var title: String {
    switch self {
    case .apiKey: "Chave de API"
    case .sshKey: "Chave SSH"
    case .token: "Token"
    case .recoveryCodes: "Códigos de recuperação"
    }
  }
}
