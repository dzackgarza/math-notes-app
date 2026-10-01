# toastification 3.2.0, patched

A copy of [toastification](https://github.com/payam-zahedi/toastification)
3.2.0 (BSD 3-Clause, `LICENSE`) with one change, in
`ToastificationManager.dismiss` (`lib/src/core/toastification_manager.dart`):
a dismissed toast is disposed, and the overlay removed, after the list's
removal animation ends, not after a fixed delay. The fixed delay removed the
overlay mid-animation when frames lagged, and the list's animation controller
was disposed twice (upstream issues #54 and #97).
