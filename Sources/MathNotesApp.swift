import Combine
import Foundation
import InkEngine
import SwiftUI
import UIKit
import os

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

  // SideStore adds the scheme sidestore-<bundle identifier> to the apps it
  // installs, and its Open button launches the app with that URL: a launch,
  // not a document.
  func receiveIncomingDocumentURL(_ url: URL) {
    if url.scheme?.lowercased() == "sidestore-\(Bundle.main.bundleIdentifier!)".lowercased() { return }
    incomingDocument = IncomingDocument(url: url)
  }

  private func receive(_ contexts: Set<UIOpenURLContext>) {
    for context in contexts {
      Log.app.info(
        "opened with URL scheme=\(context.url.scheme ?? "none", privacy: .public) extension=\(context.url.pathExtension, privacy: .public) source=\(context.options.sourceApplication ?? "unknown", privacy: .public) inPlace=\(context.options.openInPlace, privacy: .public) path=\(context.url.path, privacy: .public)")
    }
    guard let context = contexts.first else { return }
    receiveIncomingDocumentURL(context.url)
  }
}

@MainActor
final class MathNotesAppDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    do {
      try CrashReporting.install()
    } catch {
      fatalError("Crash reporting did not install: \(error)")
    }
    InputTrace.install()
    // The engine reports its input decisions: routes, commits, discards, erasing.
    ink_set_log_handler { message in
      guard let message else { return }
      Log.engine.info("\(String(cString: message), privacy: .public)")
    }
    return true
  }

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
