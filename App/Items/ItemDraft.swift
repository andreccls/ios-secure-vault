import Foundation
import VaultCore

enum DraftError: LocalizedError, Equatable {
  case missingTitle
  case invalidAuthenticator
  case missingSecret

  var errorDescription: String? {
    switch self {
    case .missingTitle: "Informe um título."
    case .invalidAuthenticator: "Segredo inválido. Use base32 (A–Z, 2–7) ou uma URI otpauth://."
    case .missingSecret: "Informe o valor secreto."
    }
  }
}

/// Editable form state for any item kind; turns into a validated `VaultItem`. Kept free of SwiftUI for tests.
struct ItemDraft: Equatable {
  let kind: ItemKind
  var title = ""
  var isFavorite = false
  // Password
  var username = ""
  var password = ""
  var url = ""
  var notes = ""
  // Authenticator (digits/period/algorithm are only editable through an otpauth:// URI)
  var issuer = ""
  var account = ""
  var secretInput = ""
  var algorithm = OTPAlgorithm.sha1
  var digits = 6
  var period = 30
  // Authentication key
  var keyKind = AuthKeyKind.apiKey

  init(kind: ItemKind) { self.kind = kind }

  init(item: VaultItem) {
    self.init(kind: item.kind)
    title = item.title
    isFavorite = item.isFavorite
    switch item.content {
    case .password(let content):
      (username, password, url, notes) = (content.username, content.password, content.url, content.notes)
    case .authenticator(let content):
      (issuer, account, secretInput) = (content.issuer, content.account, content.secret)
      (algorithm, digits, period) = (content.algorithm, content.digits, content.period)
    case .authKey(let content):
      (keyKind, secretInput, notes) = (content.keyKind, content.secret, content.notes)
    }
  }

  func build(id: UUID = UUID(), createdAt: Date = Date(), now: Date = Date()) throws -> VaultItem {
    let content: ItemContent
    var title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    switch kind {
    case .password:
      content = .password(PasswordContent(username: username, password: password, url: url, notes: notes))
    case .authenticator:
      let parsed: AuthenticatorContent
      do {
        if secretInput.lowercased().hasPrefix("otpauth://") {
          parsed = try AuthenticatorContent(otpauthURI: secretInput)
        } else {
          parsed = try AuthenticatorContent(
            issuer: issuer, account: account, secretInput: secretInput, algorithm: algorithm, digits: digits,
            period: period)
        }
      } catch {
        throw DraftError.invalidAuthenticator
      }
      if title.isEmpty { title = parsed.issuer }
      content = .authenticator(parsed)
    case .authKey:
      guard !secretInput.isEmpty else { throw DraftError.missingSecret }
      content = .authKey(AuthKeyContent(keyKind: keyKind, secret: secretInput, notes: notes))
    }
    guard !title.isEmpty else { throw DraftError.missingTitle }
    return VaultItem(
      id: id, title: title, isFavorite: isFavorite, createdAt: createdAt, updatedAt: now, content: content)
  }
}
