# Crash and hang reporting on the iPad

Research date: 2026-10-09. Requested by the user after build 293 hung at
launch on a Dropbox folder and every relaunch hung again, with no report and
no way back into the app.

## KSCrash owns crash, hang and termination capture

Select [KSCrash](https://github.com/kstenerud/KSCrash) 2.6.0 (SwiftPM,
MIT). It catches Mach exceptions, signals, C++ and Objective-C exceptions,
main-thread hangs from 250 ms with full backtraces (the watchdog monitor),
and records why the previous run ended (`previousTerminationReason`: crash,
hang, memory limit, clean exit). Reports are Apple-format capable
(`CrashReportFilterAppleFmt`) and decode into the typed `KSCrashReportModel`.
[README](https://github.com/kstenerud/KSCrash/blob/2.6.0/README.md),
[`KSTerminationReason.h`](https://github.com/kstenerud/KSCrash/blob/2.6.0/Sources/KSCrashRecording/include/KSTerminationReason.h).

Candidates searched:

- **MetricKit.** Delivers crash and hang diagnostics on the next launch, but
  developers report no payloads outside TestFlight and App Store installs,
  for new bundle IDs, and for hangs in particular
  ([Sentry #1661](https://github.com/getsentry/sentry-cocoa/issues/1661),
  [Apple forum 691147](https://developer.apple.com/forums/thread/691147),
  [Apple forum 806457](https://developer.apple.com/forums/thread/806457)).
  Math Notes is sideloaded through SideStore, so MetricKit cannot be the
  reporter.
- **Sentry, Crashlytics.** Report to a hosted service with an account and a
  key built into the app. The IPA is published on a public release page, so
  any key in it is public.
- **PLCrashReporter.** Crashes only; no hang capture and no previous-run
  termination reason.

## What the app adds

The integration gap is the user-facing part, which no candidate owns:

- **Crash-loop guard.** When the previous run ended in a crash or a hang,
  the app starts without reconnecting the saved notes folder and says why,
  offering to reconnect, choose another folder, or report the problem.
- **Report problem.** Opens GitHub's new-issue page for this repository with
  the title and body filled in: build, reason, and the crashed or hung
  thread's frames with image UUIDs, which the published dSYM symbolicates.
  The user submits it. The app holds no GitHub credentials.
- **Full report.** The Apple-format text of the report is shared through the
  system share sheet, for attaching to the issue.
