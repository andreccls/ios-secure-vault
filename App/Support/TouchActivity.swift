import SwiftUI
import UIKit

/// Reports every touch-down anywhere in the window without taking part in gesture resolution
/// (a SwiftUI `simultaneousGesture` on the root swallowed taps on toolbar buttons).
struct TouchActivity: UIViewRepresentable {
  let onTouch: @MainActor () -> Void

  func makeUIView(context: Context) -> UIView { Catcher(onTouch: onTouch) }
  func updateUIView(_ uiView: UIView, context: Context) {}

  private final class Catcher: UIView {
    let onTouch: @MainActor () -> Void
    private var recognizer: PassiveRecognizer?

    init(onTouch: @escaping @MainActor () -> Void) {
      self.onTouch = onTouch
      super.init(frame: .zero)
      isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func didMoveToWindow() {
      super.didMoveToWindow()
      guard let window, recognizer == nil else { return }
      let new = PassiveRecognizer(onTouch: onTouch)
      window.addGestureRecognizer(new)
      recognizer = new
    }
  }

  private final class PassiveRecognizer: UIGestureRecognizer {
    let onTouch: @MainActor () -> Void

    init(onTouch: @escaping @MainActor () -> Void) {
      self.onTouch = onTouch
      super.init(target: nil, action: nil)
      cancelsTouchesInView = false
      delaysTouchesBegan = false
      delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
      MainActor.assumeIsolated { onTouch() }
      state = .failed
    }
  }
}
