import SwiftUI

@MainActor
struct ResizableEditorSplitView<Primary: View, Secondary: View>: View {
  let axis: EditorSplitAxis
  @Binding var fraction: Double
  let primary: Primary
  let secondary: Secondary

  init(
    axis: EditorSplitAxis,
    fraction: Binding<Double>,
    @ViewBuilder primary: () -> Primary,
    @ViewBuilder secondary: () -> Secondary
  ) {
    self.axis = axis
    _fraction = fraction
    self.primary = primary()
    self.secondary = secondary()
  }

  var body: some View {
    GeometryReader { geometry in
      let total = axis == .horizontal
        ? geometry.size.width
        : geometry.size.height
      let usable = max(0, total - Self.dividerThickness)
      let first = usable * CGFloat(clampedFraction)

      Group {
        if axis == .horizontal {
          HStack(spacing: 0) {
            primary
              .frame(width: first)
            divider(total: total)
              .frame(width: Self.dividerThickness)
            secondary
              .frame(maxWidth: .infinity)
          }
        } else {
          VStack(spacing: 0) {
            primary
              .frame(height: first)
            divider(total: total)
              .frame(height: Self.dividerThickness)
            secondary
              .frame(maxHeight: .infinity)
          }
        }
      }
      .coordinateSpace(name: Self.coordinateSpace)
    }
  }

  private var clampedFraction: Double {
    min(max(fraction, Self.minimumFraction), Self.maximumFraction)
  }

  private func divider(total: CGFloat) -> some View {
    Rectangle()
      .fill(Color.clear)
      .overlay {
        if axis == .horizontal {
          Rectangle()
            .fill(Color.secondary.opacity(0.35))
            .frame(width: 1)
        } else {
          Rectangle()
            .fill(Color.secondary.opacity(0.35))
            .frame(height: 1)
        }
      }
      .contentShape(Rectangle())
      .gesture(
        DragGesture(
          minimumDistance: 0,
          coordinateSpace: .named(Self.coordinateSpace)
        )
        .onChanged { value in
          let usable = max(1, total - Self.dividerThickness)
          let position = axis == .horizontal
            ? value.location.x
            : value.location.y
          let normalized =
            (position - Self.dividerThickness / 2) / usable
          fraction = min(
            max(Double(normalized), Self.minimumFraction),
            Self.maximumFraction)
        })
      .accessibilityElement()
      .accessibilityLabel("Split divider")
      .accessibilityValue("\(Int(clampedFraction * 100)) percent")
      .accessibilityAdjustableAction { direction in
        let delta = switch direction {
        case .increment: 0.05
        case .decrement: -0.05
        @unknown default: 0.0
        }
        fraction = min(
          max(clampedFraction + delta, Self.minimumFraction),
          Self.maximumFraction)
      }
  }

  private static var dividerThickness: CGFloat { 12 }
  private static var minimumFraction: Double { 0.0 }
  private static var maximumFraction: Double { 1.0 }
  private static var coordinateSpace: String { "editor-split" }
}
