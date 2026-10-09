import SwiftUI

// Shown at launch when the previous run crashed or hung. The saved notes
// folder was not reconnected; the library offers to reconnect it.
struct PreviousFailureSheet: View {
  let failure: PreviousFailure
  let onClose: () -> Void
  @Environment(\.openURL) private var openURL
  @State private var fullReport: String?
  @State private var reportError: String?

  private var appVersion: String {
    let info = Bundle.main.infoDictionary ?? [:]
    return "\(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))"
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Text(failure.hang
            ? "The last time it ran, Math Notes stopped responding and iPadOS closed it."
            : "The last time it ran, Math Notes crashed.")
          Text("Your notes folder was not reconnected, so the same problem cannot happen again on launch. Reconnect it from the library when you are ready.")
            .foregroundStyle(.secondary)
        }
        Section {
          Button("Report problem on GitHub") {
            openURL(failure.issueURL(appVersion: appVersion))
          }
          if let fullReport {
            ShareLink("Share full report", item: fullReport)
          } else if let reportError {
            Text(reportError).foregroundStyle(.red)
          } else {
            ProgressView("Preparing full report…")
          }
        } footer: {
          Text("The GitHub page opens filled in. Attach the full report to the issue.")
        }
      }
      .navigationTitle(failure.summary)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done", action: onClose)
        }
      }
    }
    .task {
      do {
        fullReport = try await CrashReporting.appleFormat(reportID: failure.reportID)
      } catch {
        reportError = error.localizedDescription
      }
    }
  }
}
