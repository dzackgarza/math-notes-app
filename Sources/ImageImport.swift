import CoreGraphics
import Foundation

enum ImageImportError: LocalizedError {
  case invalidImageSize

  var errorDescription: String? {
    switch self {
    case .invalidImageSize:
      "The selected image has invalid dimensions."
    }
  }
}

func imageImportSVG(
  data: Data,
  mimeType: String,
  imageSize: CGSize,
  pageSize: CGSize
) throws -> String {
  guard imageSize.width > 0, imageSize.height > 0,
    pageSize.width > 0, pageSize.height > 0
  else { throw ImageImportError.invalidImageSize }

  let scale = min(
    1,
    pageSize.width * 0.8 / imageSize.width,
    pageSize.height * 0.8 / imageSize.height)
  let width = imageSize.width * scale
  let height = imageSize.height * scale
  let href = "data:\(mimeType);base64,\(data.base64EncodedString())"
  return """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1"><g id="import"><image href="\(href)" x="\(-width - 1)" y="\(-height - 1)" width="\(width)" height="\(height)"/></g></svg>
    """
}
