import UIKit
import XCTest
@testable import MathNotes

final class NativeThemeTests: XCTestCase {
  func testBoundVolumesFontsAreRegistered() {
    XCTAssertNotNil(UIFont(name: NativeTheme.interfaceRegularName, size: 18))
    XCTAssertNotNil(UIFont(name: NativeTheme.interfaceMediumName, size: 18))
    XCTAssertNotNil(UIFont(name: NativeTheme.interfaceExtraBoldName, size: 18))
    XCTAssertNotNil(UIFont(name: NativeTheme.volumeFontName, size: 18))
  }
}
