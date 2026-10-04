import SwiftUI

enum CreationSheetLayoutMetrics {
  static let maxWidth: CGFloat = 720
  static let splitThreshold: CGFloat = 600
  static let previewWidth: CGFloat = 260
  static let previewHeight: CGFloat = 280
}

@MainActor
struct CreationSheetLayout<Fields: View, Preview: View>: View {
  private let fields: () -> Fields
  private let preview: () -> Preview

  init(
    @ViewBuilder fields: @escaping () -> Fields,
    @ViewBuilder preview: @escaping () -> Preview
  ) {
    self.fields = fields
    self.preview = preview
  }

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .top, spacing: 0) {
        Form {
          fields()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        Divider()

        VStack(alignment: .leading, spacing: 12) {
          Text("Preview")
            .font(NativeTheme.headline)
          preview()
            .frame(maxWidth: .infinity)
            .frame(height: CreationSheetLayoutMetrics.previewHeight)
        }
        .padding(20)
        .frame(
          width: CreationSheetLayoutMetrics.previewWidth,
          maxHeight: .infinity,
          alignment: .top)
      }
      .frame(
        minWidth: CreationSheetLayoutMetrics.splitThreshold,
        maxWidth: CreationSheetLayoutMetrics.maxWidth,
        maxHeight: .infinity)

      Form {
        fields()
        Section("Preview") {
          preview()
            .frame(maxWidth: .infinity)
            .frame(height: CreationSheetLayoutMetrics.previewHeight)
        }
      }
      .frame(maxWidth: CreationSheetLayoutMetrics.maxWidth)
    }
  }
}
