import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageImportError: LocalizedError {
  case invalidImageSize
  case notSVG
  case undecodableImage
  case unsupportedFile(String)
  case unencodableImage

  var errorDescription: String? {
    switch self {
    case .invalidImageSize:
      "The selected image has invalid dimensions."
    case .notSVG:
      "The dropped or pasted text is not an SVG document."
    case .undecodableImage:
      "The image could not be read."
    case let .unsupportedFile(name):
      "\(name) is neither an image nor an SVG document."
    case .unencodableImage:
      "The image could not be converted to PNG."
    }
  }
}

// What a drop, paste or import inserts: an SVG document as given, or a raster
// image placed at a size that fits the page.
enum ImportedContent {
  case svg(Data)
  case image(Data)

  // A file by its extension.
  init(file url: URL, data: Data) throws {
    guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else {
      throw ImageImportError.unsupportedFile(url.lastPathComponent)
    }
    if type.conforms(to: .svg) {
      self = .svg(data)
    } else if type.conforms(to: .image) {
      self = .image(data)
    } else {
      throw ImageImportError.unsupportedFile(url.lastPathComponent)
    }
  }

  func svg(pageSize: CGSize) throws -> String {
    switch self {
    case let .svg(data):
      guard let text = String(data: data, encoding: .utf8), text.contains("<svg") else {
        throw ImageImportError.notSVG
      }
      return text
    case let .image(data):
      return try rasterImportSVG(data, pageSize: pageSize)
    }
  }
}

// A raster image as an SVG <image>, upright. PNG and JPEG bytes are kept when
// the image carries no rotation; anything else is drawn upright and stored as
// PNG (ImageIO: kCGImageSourceCreateThumbnailWithTransform, WWDC18 219).
private func rasterImportSVG(_ data: Data, pageSize: CGSize) throws -> String {
  guard let source = CGImageSourceCreateWithData(data as CFData, nil),
    let typeID = CGImageSourceGetType(source),
    let type = UTType(typeID as String),
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
    let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int,
    let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int
  else { throw ImageImportError.undecodableImage }
  // An image without an orientation property is upright (EXIF/TIFF tag 274 default 1).
  let orientation = properties[kCGImagePropertyOrientation] as? UInt32 ?? 1
  if orientation == 1, type == .png || type == .jpeg {
    return try imageImportSVG(
      data: data, mimeType: type == .png ? "image/png" : "image/jpeg",
      imageSize: CGSize(width: pixelWidth, height: pixelHeight), pageSize: pageSize)
  }
  let options: [CFString: Any] = [
    kCGImageSourceCreateThumbnailFromImageAlways: true,
    kCGImageSourceCreateThumbnailWithTransform: true,
    kCGImageSourceThumbnailMaxPixelSize: max(pixelWidth, pixelHeight),
  ]
  guard let upright = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
    throw ImageImportError.undecodableImage
  }
  let png = NSMutableData()
  guard let destination = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil) else {
    throw ImageImportError.unencodableImage
  }
  CGImageDestinationAddImage(destination, upright, nil)
  guard CGImageDestinationFinalize(destination) else { throw ImageImportError.unencodableImage }
  return try imageImportSVG(
    data: png as Data, mimeType: "image/png",
    imageSize: CGSize(width: upright.width, height: upright.height), pageSize: pageSize)
}

func imageImportSVG(
  data: Data,
  mimeType: String,
  imageSize: CGSize,
  pageSize: CGSize
) throws -> String {
  guard imageSize.width.isFinite, imageSize.height.isFinite,
    pageSize.width.isFinite, pageSize.height.isFinite,
    imageSize.width > 0, imageSize.height > 0,
    pageSize.width > 0, pageSize.height > 0
  else { throw ImageImportError.invalidImageSize }

  let scale = min(
    1,
    pageSize.width * 0.8 / imageSize.width,
    pageSize.height * 0.8 / imageSize.height)
  let width = imageSize.width * scale
  let height = imageSize.height * scale
  guard width.isFinite, height.isFinite, width > 0, height > 0 else {
    throw ImageImportError.invalidImageSize
  }
  let href = "data:\(mimeType);base64,\(data.base64EncodedString())"
  return """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1"><g id="import"><image href="\(href)" x="\(-width - 1)" y="\(-height - 1)" width="\(width)" height="\(height)"/></g></svg>
    """
}
