import Foundation

public enum ItemKind: String, Codable, CaseIterable, Sendable {
  case password
  case authenticator
  case authKey
}

public enum AuthKeyKind: String, Codable, CaseIterable, Sendable {
  case apiKey
  case sshKey
  case token
  case recoveryCodes
}

public struct PasswordContent: Codable, Hashable, Sendable {
  public var username: String
  public var password: String
  public var url: String
  public var notes: String

  public init(username: String = "", password: String = "", url: String = "", notes: String = "") {
    self.username = username
    self.password = password
    self.url = url
    self.notes = notes
  }
}

public struct AuthKeyContent: Codable, Hashable, Sendable {
  public var keyKind: AuthKeyKind
  public var secret: String
  public var notes: String

  public init(keyKind: AuthKeyKind = .apiKey, secret: String = "", notes: String = "") {
    self.keyKind = keyKind
    self.secret = secret
    self.notes = notes
  }
}

/// One case per item type. To add a new type: add a case here, a `kind`, and the UI (docs/ARCHITECTURE.md).
public enum ItemContent: Codable, Hashable, Sendable {
  case password(PasswordContent)
  case authenticator(AuthenticatorContent)
  case authKey(AuthKeyContent)

  public var kind: ItemKind {
    switch self {
    case .password: .password
    case .authenticator: .authenticator
    case .authKey: .authKey
    }
  }
}

/// A decrypted vault entry. Everything here (title included) is encrypted at rest as a single AES-GCM blob.
public struct VaultItem: Codable, Hashable, Identifiable, Sendable {
  public let id: UUID
  public var title: String
  public var isFavorite: Bool
  public let createdAt: Date
  public var updatedAt: Date
  public var content: ItemContent

  public var kind: ItemKind { content.kind }

  public init(
    id: UUID = UUID(), title: String, isFavorite: Bool = false, createdAt: Date = Date(),
    updatedAt: Date? = nil, content: ItemContent
  ) {
    self.id = id
    self.title = title
    self.isFavorite = isFavorite
    self.createdAt = createdAt
    self.updatedAt = updatedAt ?? createdAt
    self.content = content
  }
}

/// In-memory search/sort over decrypted items. Secret values are never searched.
public struct ItemFilter: Equatable, Sendable {
  public var kind: ItemKind?
  public var query: String
  public var favoritesOnly: Bool

  public init(kind: ItemKind? = nil, query: String = "", favoritesOnly: Bool = false) {
    self.kind = kind
    self.query = query
    self.favoritesOnly = favoritesOnly
  }

  public func apply(to items: [VaultItem]) -> [VaultItem] {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
    return items.filter { item in
      (kind == nil || item.kind == kind) && (!favoritesOnly || item.isFavorite)
        && (needle.isEmpty
          || Self.searchableFields(of: item).contains {
            $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
          })
    }.sorted {
      if $0.isFavorite != $1.isFavorite { return $0.isFavorite }
      return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
    }
  }

  private static func searchableFields(of item: VaultItem) -> [String] {
    switch item.content {
    case .password(let content): [item.title, content.username, content.url]
    case .authenticator(let content): [item.title, content.issuer, content.account]
    case .authKey(let content): [item.title, content.keyKind.rawValue]
    }
  }
}
