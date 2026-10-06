import Foundation
import Testing
import VaultCore

@testable import SecureVault

@Suite("ItemDraft")
struct ItemDraftTests {
  @Test func passwordRequiresTitleAndBuilds() throws {
    var draft = ItemDraft(kind: .password)
    #expect(throws: DraftError.missingTitle) { try draft.build() }
    draft.title = "  Mail "
    draft.username = "alice"
    let item = try draft.build()
    #expect(item.title == "Mail")
    #expect(item.content == .password(PasswordContent(username: "alice")))
  }

  @Test func authenticatorAcceptsManualSecretAndURI() throws {
    var draft = ItemDraft(kind: .authenticator)
    draft.secretInput = "not base32!"
    #expect(throws: DraftError.invalidAuthenticator) { try draft.build() }
    draft.secretInput = "gezd gnbv"
    draft.title = "Manual"
    guard case .authenticator(let manual) = try draft.build().content else {
      Issue.record("kind")
      return
    }
    #expect(manual.secret == "GEZDGNBV")

    draft.title = ""
    draft.secretInput = "otpauth://totp/Acme:bob?secret=GEZDGNBV&digits=8"
    let item = try draft.build()
    #expect(item.title == "Acme")  // falls back to the issuer
    guard case .authenticator(let parsed) = item.content else {
      Issue.record("kind")
      return
    }
    #expect(parsed.digits == 8)
  }

  @Test func authKeyRequiresSecret() throws {
    var draft = ItemDraft(kind: .authKey)
    draft.title = "CI"
    #expect(throws: DraftError.missingSecret) { try draft.build() }
    draft.secretInput = "tok_EXAMPLE"
    draft.keyKind = .token
    #expect(try draft.build().content == .authKey(AuthKeyContent(keyKind: .token, secret: "tok_EXAMPLE")))
  }

  @Test func roundTripsExistingItemsForEditing() throws {
    let totp = try AuthenticatorContent(
      issuer: "I", account: "a", secretInput: "GEZDGNBV", digits: 7, period: 45)
    let items = [
      VaultItem(
        title: "P", isFavorite: true,
        content: .password(PasswordContent(username: "u", password: "p", url: "x", notes: "n"))),
      VaultItem(title: "T", content: .authenticator(totp)),
      VaultItem(title: "K", content: .authKey(AuthKeyContent(keyKind: .sshKey, secret: "s", notes: "n"))),
    ]
    for item in items {
      let rebuilt = try ItemDraft(item: item).build(
        id: item.id, createdAt: item.createdAt, now: item.updatedAt)
      #expect(rebuilt == item)
    }
  }

  @Test func errorsHaveMessages() {
    for error in [DraftError.missingTitle, .invalidAuthenticator, .missingSecret] {
      #expect(error.errorDescription?.isEmpty == false)
    }
  }
}

@MainActor
@Suite("GeneratorModel")
struct GeneratorModelTests {
  @Test func regeneratesWhenOptionsChange() {
    let model = GeneratorModel()
    #expect(model.generated.count == 20)
    model.options.length = 32
    #expect(model.generated.count == 32)
    let before = model.generated
    model.regenerate()
    #expect(model.generated != before)
    #expect(model.strength.level == .strong)
    #expect(model.entropyBits > 100)
  }

  @Test func lastCharacterClassCannotBeDisabled() {
    let model = GeneratorModel()
    model.options.uppercase = false
    model.options.digits = false
    model.options.symbols = false
    #expect(model.canDisable(\.lowercase) == false)
    #expect(model.canDisable(\.digits))
  }
}

@MainActor
@Suite("Clipboard and UI helpers")
struct ClipboardTests {
  final class Spy: PasteboardWriting, @unchecked Sendable {
    var written: (String, Date)?
    func write(_ string: String, expiresAt: Date) { written = (string, expiresAt) }
  }

  @Test func copiesWithExpirationAndShowsNotice() {
    let spy = Spy()
    let now = Date(timeIntervalSince1970: 1000)
    let clipboard = ClipboardService(pasteboard: spy, now: { now })
    clipboard.copy("secret", label: "Senha")
    #expect(spy.written?.0 == "secret")
    #expect(spy.written?.1 == now.addingTimeInterval(ClipboardService.expiry))
    #expect(clipboard.notice?.contains("30 s") == true)
  }

  @Test func codeFormatting() {
    #expect(AuthenticatorCodeView.grouped("123456") == "123 456")
    #expect(AuthenticatorCodeView.grouped("12345678") == "1234 5678")
    #expect(AuthenticatorCodeView.spoken("123") == "1 2 3")
  }
}
