import SwiftUI

struct RootView: View {
  let showShield: Bool
  @Environment(SessionModel.self) private var session
  @Environment(ClipboardService.self) private var clipboard
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    ZStack {
      switch session.phase {
      case .loading: ProgressView()
      case .setup: UnlockView(isSetup: true)
      case .locked: UnlockView(isSetup: false)
      case .unlocked: MainTabView()
      }
      if showShield || scenePhase != .active { PrivacyShield() }
    }
    .safeAreaInset(edge: .bottom) {
      if let notice = clipboard.notice {
        Text(notice)
          .font(.footnote)
          .padding(12)
          .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
          .padding(.horizontal)
          .transition(.move(edge: .bottom).combined(with: .opacity))
          .accessibilityAddTraits(.isStaticText)
      }
    }
    .animation(.default, value: clipboard.notice)
    // Any touch counts as activity for the inactivity timer.
    .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in session.recordActivity() })
    .onChange(of: scenePhase) { _, phase in
      if phase == .background { session.handleBackground() }
    }
    .task(id: session.phase) {
      guard session.phase == .unlocked else { return }
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))
        session.checkInactivity()
      }
    }
  }
}

/// Opaque cover shown whenever the app is not active, so the app-switcher snapshot never contains secrets.
struct PrivacyShield: View {
  var body: some View {
    ZStack {
      Rectangle().fill(.background).ignoresSafeArea()
      VStack(spacing: 12) {
        Image(systemName: "lock.shield.fill").font(.system(size: 64)).foregroundStyle(.tint)
        Text("Secure Vault").font(.title2.bold())
        Text("Conteúdo oculto").font(.subheadline).foregroundStyle(.secondary)
      }
      .accessibilityElement(children: .combine)
    }
    .accessibilityIdentifier("privacyShield")
  }
}

struct MainTabView: View {
  var body: some View {
    TabView {
      ItemListView(kind: .password).tabItem { Label("Senhas", systemImage: "key.fill") }
      ItemListView(kind: .authenticator).tabItem { Label("Códigos", systemImage: "number.circle.fill") }
      ItemListView(kind: .authKey).tabItem { Label("Chaves", systemImage: "terminal.fill") }
      SettingsView().tabItem { Label("Ajustes", systemImage: "gearshape.fill") }
    }
  }
}
