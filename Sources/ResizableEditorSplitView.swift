import SwiftUI

@MainActor
struct ResizableEditorSplitView<Primary: View, Secondary: View>: View {
  let axis: EditorSplitAxis
  @Binding var fraction: Double
  @State private var dragStartFraction: Double?
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
              .zIndex(1)
            secondary
              .frame(maxWidth: .infinity)
          }
        } else {
          VStack(spacing: 0) {
            primary
              .frame(height: first)
            divider(total: total)
              .frame(height: Self.dividerThickness)
              .zIndex(1)
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
      // The HIG's 44 pt touch target, centered on the line and over the pane edges.
      .overlay {
        Color.clear
          .frame(
            width: axis == .horizontal ? Self.touchTarget : nil,
            height: axis == .horizontal ? nil : Self.touchTarget)
          .contentShape(Rectangle())
          .gesture(
            DragGesture(coordinateSpace: .named(Self.coordinateSpace))
              .onChanged { value in
                // Relative to where the drag began, so touching the divider
                // does not move it.
                let start = dragStartFraction ?? clampedFraction
                dragStartFraction = start
                let usable = max(1, total - Self.dividerThickness)
                let moved = axis == .horizontal ? value.translation.width : value.translation.height
                fraction = min(
                  max(start + Double(moved / usable), Self.minimumFraction),
                  Self.maximumFraction)
              }
              .onEnded { _ in dragStartFraction = nil })
      }
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
  private static var touchTarget: CGFloat { 44 }
  private static var minimumFraction: Double { 0.0 }
  private static var maximumFraction: Double { 1.0 }
  private static var coordinateSpace: String { "editor-split" }
}
