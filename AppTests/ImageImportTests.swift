import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import MathNotes

// Images dropped, pasted or imported become an <image> on the page. The
// oracles are the image formats: EXIF orientation 6 means the stored image is
// shown turned 90° clockwise, and an upright PNG needs no re-encoding.
final class ImageImportTests: XCTestCase {
  func testAPhotoTaggedRotatedIsPlacedUpright() throws {
    // Stored 40 × 20, red on the left half and blue on the right.
    let stored = try twoColorImage(width: 40, height: 20)
    let jpeg = try encode(stored, as: .jpeg, orientation: 6)

    let placed = try placedImage(ImportedContent.image(jpeg).svg(pageSize: CGSize(width: 500, height: 500)))

    XCTAssertEqual(placed.mimeType, "image/png", "a rotated photo is stored upright, as PNG")
    XCTAssertEqual(placed.width, 20)
    XCTAssertEqual(placed.height, 40)
    let upright = try decode(placed.bytes)
    XCTAssertEqual(upright.width, 20)
    XCTAssertEqual(upright.height, 40)
    // Turned clockwise, the stored left half is on top.
    XCTAssertEqual(try dominantChannel(upright, x: 10, y: 5), 0, "the top is red")
    XCTAssertEqual(try dominantChannel(upright, x: 10, y: 35), 2, "the bottom is blue")
  }

  func testAnUprightPNGKeepsItsBytesAndAWideOneFitsEightyPercentOfThePage() throws {
    let png = try encode(try twoColorImage(width: 1000, height: 500), as: .png, orientation: nil)

    let placed = try placedImage(ImportedContent.image(png).svg(pageSize: CGSize(width: 500, height: 500)))

    XCTAssertEqual(placed.mimeType, "image/png")
    XCTAssertEqual(placed.bytes, png)
    XCTAssertEqual(placed.width, 400)
    XCTAssertEqual(placed.height, 200)
  }

  func testTextThatIsNotAnSVGDocumentIsRejected() {
    XCTAssertThrowsError(try ImportedContent.svg(Data("a lecture outline".utf8)).svg(pageSize: CGSize(width: 500, height: 500))) {
      guard case ImageImportError.notSVG = $0 else { return XCTFail("expected notSVG, got \($0)") }
    }
  }

  private func twoColorImage(width: Int, height: Int) throws -> CGImage {
    let context = try XCTUnwrap(CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
    context.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
    context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
    return try XCTUnwrap(context.makeImage())
  }

  private func encode(_ image: CGImage, as type: UTType, orientation: UInt32?) throws -> Data {
    let data = NSMutableData()
    let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
    let properties = orientation.map { [kCGImagePropertyOrientation: $0] as CFDictionary }
    CGImageDestinationAddImage(destination, image, properties)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    return data as Data
  }

  private func decode(_ data: Data) throws -> CGImage {
    let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
    return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
  }

  // 0 red, 1 green, 2 blue: the strongest channel at a pixel, top-left origin.
  private func dominantChannel(_ image: CGImage, x: Int, y: Int) throws -> Int {
    var pixel = [UInt8](repeating: 0, count: 4)
    let context = try XCTUnwrap(CGContext(
      data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
    let rgb = pixel.prefix(3).map(Int.init)
    return rgb.firstIndex(of: rgb.max()!)!
  }

  private struct PlacedImage {
    let mimeType: String
    let bytes: Data
    let width: Double
    let height: Double
  }

  private func placedImage(_ svg: String) throws -> PlacedImage {
    let reader = ImageElementReader()
    let parser = XMLParser(data: Data(svg.utf8))
    parser.delegate = reader
    XCTAssertTrue(parser.parse(), "the import SVG is not well-formed")
    let attributes = try XCTUnwrap(reader.image, "the import SVG has no <image>")
    let href = try XCTUnwrap(attributes["href"])
    let prefix = try XCTUnwrap(href.range(of: ";base64,"))
    return PlacedImage(
      mimeType: String(href[href.index(href.startIndex, offsetBy: 5)..<prefix.lowerBound]),
      bytes: try XCTUnwrap(Data(base64Encoded: String(href[prefix.upperBound...]))),
      width: try XCTUnwrap(Double(try XCTUnwrap(attributes["width"]))),
      height: try XCTUnwrap(Double(try XCTUnwrap(attributes["height"]))))
  }
}

private final class ImageElementReader: NSObject, XMLParserDelegate {
  var image: [String: String]?

  func parser(
    _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
    qualifiedName: String?, attributes: [String: String]
  ) {
    if elementName == "image" { image = attributes }
  }
}
