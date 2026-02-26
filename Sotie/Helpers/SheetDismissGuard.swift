import SwiftUI
import UIKit

/// A transparent UIViewRepresentable that detects when the user
/// attempts to interactively dismiss a sheet that has `interactiveDismissDisabled(true)`.
///
/// Uses the UIResponder chain to reliably find the sheet's presentation controller
/// and attach a delegate that fires on dismiss attempts.
///
/// Usage:
/// ```swift
/// .background(SheetDismissGuard(onDismissAttempt: $showConfirmation))
/// ```
struct SheetDismissGuard: UIViewRepresentable {
  @Binding var onDismissAttempt: Bool

  func makeUIView(context: Context) -> SheetDismissGuardView {
    let view = SheetDismissGuardView()
    view.coordinator = context.coordinator
    return view
  }

  func updateUIView(_ uiView: SheetDismissGuardView, context: Context) {
    uiView.coordinator = context.coordinator
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(onDismissAttempt: $onDismissAttempt)
  }

  // MARK: - Coordinator (Delegate)

  final class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate {
    @Binding var onDismissAttempt: Bool

    init(onDismissAttempt: Binding<Bool>) {
      _onDismissAttempt = onDismissAttempt
    }

    func presentationControllerDidAttemptToDismiss(
      _ presentationController: UIPresentationController
    ) {
      // Haptic feedback to signal the sheet is blocked
      let generator = UINotificationFeedbackGenerator()
      generator.notificationOccurred(.warning)

      // iOS automatically dismisses the keyboard when presenting a system alert,
      // so no manual resignFirstResponder or delay needed.
      onDismissAttempt = true
    }

    // NOTE: We intentionally do NOT implement presentationControllerShouldDismiss.
    // This lets the system use SwiftUI's `interactiveDismissDisabled` (isModalInPresentation)
    // to decide whether to allow dismiss. We only need the callback when it's blocked.
  }
}

// MARK: - Guard View

/// Invisible UIView that hooks into the sheet's presentation controller via the responder chain.
final class SheetDismissGuardView: UIView {
  weak var coordinator: SheetDismissGuard.Coordinator?
  private var didSetupDelegate = false

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window != nil {
      setupDelegate()
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    // Retry on layout passes in case the hierarchy wasn't ready in didMoveToWindow
    if !didSetupDelegate {
      setupDelegate()
    }
  }

  private func setupDelegate() {
    guard let coordinator = coordinator else { return }

    // Walk up the responder chain to find the VC with a presentation controller
    var responder: UIResponder? = self
    while let next = responder {
      if let vc = next as? UIViewController,
        let pc = vc.presentationController
      {
        if pc.delegate !== coordinator {
          pc.delegate = coordinator
        }
        didSetupDelegate = true
        return
      }
      responder = next.next
    }
  }
}
