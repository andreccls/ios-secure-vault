import SwiftUI
import VaultCore

/// Live TOTP code with a countdown ring. `TimelineView` redraws once per second; nothing is stored or timed by us.
struct AuthenticatorCodeView: View {
  let content: AuthenticatorContent
  var large = false
  @Environment(ClipboardService.self) private var clipboard

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      let code = content.code(at: context.date)
      let remaining = content.secondsRemaining(at: context.date)
      HStack(spacing: 12) {
        Text(Self.grouped(code))
          .font(.system(large ? .largeTitle : .title2, design: .monospaced).weight(.semibold))
          .minimumScaleFactor(0.6)
          .foregroundStyle(remaining <= 5 ? Color.red : Color.primary)
          .contentTransition(.numericText())
        Spacer(minLength: 0)
        Countdown(remaining: remaining, period: content.period)
        Button {
          clipboard.copy(code, label: "Código")
        } label: {
          Image(systemName: "doc.on.doc")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Copiar código")
      }
      .accessibilityElement(children: .contain)
      .accessibilityValue("\(Self.spoken(code)), expira em \(remaining) segundos")
      .accessibilityAddTraits(.updatesFrequently)
    }
  }

  static func grouped(_ code: String) -> String {
    let half = code.count / 2
    return "\(code.prefix(half)) \(code.dropFirst(half))"
  }

  static func spoken(_ code: String) -> String { code.map(String.init).joined(separator: " ") }
}

struct Countdown: View {
  let remaining: Int
  let period: Int

  var body: some View {
    ZStack {
      Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 3)
      Circle().trim(from: 0, to: Double(remaining) / Double(period))
        .stroke(remaining <= 5 ? Color.red : Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
        .rotationEffect(.degrees(-90))
      Text("\(remaining)").font(.caption2.monospacedDigit())
    }
    .frame(width: 32, height: 32)
    .accessibilityHidden(true)
  }
}
