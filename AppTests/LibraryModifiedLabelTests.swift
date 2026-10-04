import XCTest
@testable import MathNotes

final class LibraryModifiedLabelTests: XCTestCase {
  func testModifiedLabelMatchesWebTodayYesterdayAndDateForms() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
    let locale = Locale(identifier: "en_US")

    func date(_ day: Int, _ hour: Int, _ minute: Int) throws -> Date {
      try XCTUnwrap(
        calendar.date(
          from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 10,
            day: day,
            hour: hour,
            minute: minute)))
    }

    let now = try date(4, 18, 0)
    XCTAssertEqual(
      libraryModifiedLabel(try date(4, 14, 47), now: now, calendar: calendar, locale: locale),
      "Today 14:47")
    XCTAssertEqual(
      libraryModifiedLabel(try date(3, 9, 5), now: now, calendar: calendar, locale: locale),
      "Yesterday 09:05")
    XCTAssertEqual(
      libraryModifiedLabel(try date(1, 12, 0), now: now, calendar: calendar, locale: locale),
      "Oct 1, 2026")
  }
}
