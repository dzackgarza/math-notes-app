import Combine
import Foundation
import SwiftUI
import UIKit

struct IncomingDocument: Equatable, Identifiable {
  let id = UUID()
  let url: URL
}

@MainActor
final class MathNotesSceneDelegate: NSObject, UIWindowSceneDelegate, ObservableObject {
  @Published private(set) var incomingDocument: IncomingDocument?

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    receive(connectionOptions.urlContexts)
  }

  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    receive(URLContexts)
  }

  func clearIncomingDocument(_ id: UUID) {
    guard incomingDocument?.id == id else { return }
    incomingDocument = nil
  }

  func receiveIncomingDocumentURL(_ url: URL) {
    incomingDocument = IncomingDocument(url: url)
  }

  private func receive(_ contexts: Set<UIOpenURLContext>) {
    guard let context = contexts.first else { return }
    receiveIncomingDocumentURL(context.url)
  }
}

@MainActor
final class MathNotesAppDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    configurationForConnecting connectingSceneSession: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    let configuration = UISceneConfiguration(
      name: nil,
      sessionRole: connectingSceneSession.role)
    if connectingSceneSession.role == .windowApplication {
      configuration.delegateClass = MathNotesSceneDelegate.self
    }
    return configuration
  }
}

@main
struct MathNotesApp: App {
  @UIApplicationDelegateAdaptor(MathNotesAppDelegate.self) private var appDelegate
  var body: some Scene {
    WindowGroup {
      ContentView()
    }
  }
}
