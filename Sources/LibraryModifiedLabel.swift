import Foundation

func libraryModifiedLabel(
  _ date: Date,
  now: Date = Date(),
  calendar inputCalendar: Calendar = .current,
  locale: Locale = .current
) -> String {
  let calendar = inputCalendar
  let dateStart = calendar.startOfDay(for: date)
  let nowStart = calendar.startOfDay(for: now)
  let days = calendar.dateComponents([.day], from: dateStart, to: nowStart).day

  let formatter = DateFormatter()
  formatter.calendar = calendar
  formatter.locale = locale
  formatter.timeZone = calendar.timeZone

  if days == 0 || days == 1 {
    formatter.setLocalizedDateFormatFromTemplate("Hm")
    let prefix = days == 0 ? "Today" : "Yesterday"
    return "\(prefix) \(formatter.string(from: date))"
  }

  formatter.setLocalizedDateFormatFromTemplate("yMMMd")
  return formatter.string(from: date)
}
