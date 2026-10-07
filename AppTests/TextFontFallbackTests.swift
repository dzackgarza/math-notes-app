import UIKit
import XCTest
@testable import MathNotes

final class TextFontFallbackTests: XCTestCase {
  func testBundledTextFallbackFontsAreRegistered() {
    for name in noteTextFallbackFontNames {
      XCTAssertNotNil(UIFont(name: name, size: 18), name)
    }
  }

  func testTextInputUsesRendererFallbackOrder() throws {
    let descriptors = try XCTUnwrap(
      noteTextFont(size: 18).fontDescriptor.object(forKey: .cascadeList)
        as? [UIFontDescriptor])
    XCTAssertEqual(descriptors.compactMap(\.postscriptName), noteTextFallbackFontNames)
  }
}
