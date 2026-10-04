import CoreGraphics

struct FitScrollPosition {
  static func leadingDocumentCoordinate(
    contentOffset: CGFloat,
    leadingInset: CGFloat,
    zoomScale: CGFloat
  ) -> CGFloat? {
    guard zoomScale > 0 else { return nil }
    return (contentOffset + leadingInset) / zoomScale
  }

  static func contentOffset(
    for documentCoordinate: CGFloat,
    leadingInset: CGFloat,
    zoomScale: CGFloat,
    minimum: CGFloat,
    maximum: CGFloat
  ) -> CGFloat {
    min(max(documentCoordinate * zoomScale - leadingInset, minimum), maximum)
  }
}
