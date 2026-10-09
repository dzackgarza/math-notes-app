import Foundation
import KSCrashFilters
import KSCrashRecording
import KSCrashReportModel

// Crash, hang and termination capture belongs to KSCrash; the app adds the
// crash-loop guard and the prefilled GitHub issue
// (docs/research_notes/Component ownership decisions/diagnostics.md).
enum CrashReporting {
  static let issuesURL = URL(string: "https://github.com/dzackgarza/math-notes-app/issues/new")!

  static func install() throws {
    // The default monitors are the production set, which includes the
    // watchdog (main-thread hangs with backtraces) and termination monitors.
    try KSCrash.shared.install(with: KSCrashConfiguration())
    let reason = KSCrash.shared.previousTerminationReason
    Log.app.notice(
      "previous run ended: \(String(cString: kstermination_reasonToString(reason)), privacy: .public); stored reports: \(KSCrash.shared.reportStore?.reportCount ?? 0, privacy: .public)")
  }

  // How the previous run ended, when it was a crash or a hang: the app then
  // starts without reconnecting the saved notes folder.
  static func previousFailure() throws -> PreviousFailure? {
    let reason = KSCrash.shared.previousTerminationReason
    guard reason == .crash || reason == .hang else { return nil }
    guard let store = KSCrash.shared.reportStore, let id = store.reportIDs.last?.int64Value else {
      throw CrashReportingError.missingReport(String(cString: kstermination_reasonToString(reason)))
    }
    guard let data = store.reportData(for: id)?.value else {
      throw CrashReportingError.missingReport(String(cString: kstermination_reasonToString(reason)))
    }
    let report = try JSONDecoder().decode(KSCrashReportModel.CrashReport<NoUserData>.self, from: data)
    return PreviousFailure(hang: reason == .hang, reportID: id, report: report)
  }

  // The Apple-format text of a stored report, for the share sheet.
  static func appleFormat(reportID: Int64) async throws -> String {
    guard let store = KSCrash.shared.reportStore, let report = store.report(for: reportID) else {
      throw CrashReportingError.missingReport("report \(reportID)")
    }
    let filter = CrashReportFilterAppleFmt(reportStyle: .symbolicatedSideBySide)
    return try await withCheckedThrowingContinuation { continuation in
      filter.filterReports([report]) { reports, error in
        if let error { return continuation.resume(throwing: error) }
        guard let text = (reports?.first as? CrashReportString)?.value else {
          return continuation.resume(throwing: CrashReportingError.missingReport("Apple format of report \(reportID)"))
        }
        continuation.resume(returning: text)
      }
    }
  }

  static func forget(_ failure: PreviousFailure) {
    KSCrash.shared.reportStore?.deleteReport(with: failure.reportID)
  }
}

enum CrashReportingError: LocalizedError {
  case missingReport(String)

  var errorDescription: String? {
    switch self {
    case .missingReport(let what): "The crash report for \(what) is missing."
    }
  }
}

struct PreviousFailure: Identifiable {
  let hang: Bool
  let reportID: Int64
  let report: KSCrashReportModel.CrashReport<NoUserData>

  var id: Int64 { reportID }

  var summary: String { hang ? "Math Notes stopped responding" : "Math Notes crashed" }

  // The thread that crashed, or for a hang the main thread.
  private var thread: KSCrashReportModel.Thread? {
    report.crash.crashedThread
      ?? report.crash.threads?.first(where: { $0.crashed })
      ?? report.crash.threads?.first(where: { $0.index == 0 })
  }

  // GitHub's new-issue page for this repository, filled in. The frames keep
  // their image UUIDs and addresses, which the release's dSYM symbolicates.
  func issueURL(appVersion: String) -> URL {
    let frames = (thread?.backtrace?.contents ?? []).prefix(40).enumerated().map { index, frame in
      let image = frame.objectName ?? "?"
      let symbol = frame.symbolName.map { " \($0)" } ?? ""
      return String(format: "%2d %@ 0x%llx%@", index, image, frame.instructionAddr, symbol)
    }
    let images = Set((thread?.backtrace?.contents ?? []).compactMap { frame in
      frame.objectName.flatMap { name in frame.objectUUID.map { "\(name) \($0)" } }
    }).sorted()
    let body = """
      \(summary) (build \(appVersion), report \(report.report.id)).

      Error: \(report.crash.error.type.rawValue)\(report.crash.diagnosis.map { ", \($0)" } ?? "")

      Thread \(thread?.index ?? -1)\(thread?.name.map { " (\($0))" } ?? ""):
      ```
      \(frames.joined(separator: "\n"))
      ```

      Images:
      ```
      \(images.joined(separator: "\n"))
      ```
      """
    var components = URLComponents(url: CrashReporting.issuesURL, resolvingAgainstBaseURL: false)!
    components.queryItems = [
      URLQueryItem(name: "title", value: "iPad \(appVersion): \(summary)"),
      URLQueryItem(name: "body", value: body),
    ]
    return components.url!
  }
}
