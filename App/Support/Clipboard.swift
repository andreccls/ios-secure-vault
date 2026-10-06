import Foundation
import Observation
import UIKit
import UniformTypeIdentifiers

protocol PasteboardWriting: Sendable {
  func write(_ string: String, expiresAt: Date)
}

/// `localOnly` keeps the value off Universal Clipboard; `expirationDate` makes iOS clear it by itself.
struct SystemPasteboard: PasteboardWriting {
  func write(_ string: String, expiresAt: Date) {
    UIPasteboard.general.setItems(
      [[UTType.utf8PlainText.identifier: string]],
      options: [.localOnly: true, .expirationDate: expiresAt])
  }
}

@MainActor @Observable
final class ClipboardService {
  static let expiry: TimeInterval = 30

  private(set) var notice: String?
  @ObservationIgnored private let pasteboard: PasteboardWriting
  @ObservationIgnored private let now: @Sendable () -> Date
  @ObservationIgnored private var dismissTask: Task<Void, Never>?

  init(pasteboard: PasteboardWriting = SystemPasteboard(), now: @escaping @Sendable () -> Date = { Date() }) {
    self.pasteboard = pasteboard
    self.now = now
  }

  func copy(_ value: String, label: String) {
    pasteboard.write(value, expiresAt: now().addingTimeInterval(Self.expiry))
    notice = "\(label) copiado. Será apagado da área de transferência em \(Int(Self.expiry)) s."
    dismissTask?.cancel()
    dismissTask = Task {
      try? await Task.sleep(for: .seconds(3))
      if !Task.isCancelled { notice = nil }
    }
  }
}
