import CoreGraphics

struct FitScrollPosition {
  static func leadingDocumentCoordinate(
    contentOffset: CGFloat,
    leadingInset: CGFloat,
    zoomScale: CGFloat
  ) -> CGFloat? {
    guard contentOffset.isFinite, leadingInset.isFinite, zoomScale.isFinite, zoomScale > 0 else { return nil }
    let coordinate = (contentOffset + leadingInset) / zoomScale
    return coordinate.isFinite ? coordinate : nil
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
