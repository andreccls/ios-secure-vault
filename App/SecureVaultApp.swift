import SwiftUI
import VaultCore

@main
struct SecureVaultApp: App {
  @State private var composition = AppComposition.make()

  var body: some Scene {
    WindowGroup {
      RootView(showShield: composition.showShield)
        .environment(composition.session)
        .environment(composition.clipboard)
        .task {
          #if DEBUG
            await DemoData.seedIfRequested(composition.vault)
          #endif
          await composition.session.bootstrap()
        }
    }
  }
}
