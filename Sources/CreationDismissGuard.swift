import SwiftUI
import UIKit

@MainActor
struct CreationDismissGuard: UIViewControllerRepresentable {
  let onAttempt: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(onAttempt: onAttempt)
  }

  func makeUIViewController(context: Context) -> UIViewController {
    UIViewController()
  }

  func updateUIViewController(_ controller: UIViewController, context: Context) {
    context.coordinator.onAttempt = onAttempt
    DispatchQueue.main.async {
      guard let presentation = controller.parent?.presentationController
        ?? controller.presentationController
      else { return }
      presentation.delegate = context.coordinator
    }
  }

  final class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate {
    var onAttempt: () -> Void

    init(onAttempt: @escaping () -> Void) {
      self.onAttempt = onAttempt
    }

    func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
      false
    }

    func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
      onAttempt()
    }
  }
}
