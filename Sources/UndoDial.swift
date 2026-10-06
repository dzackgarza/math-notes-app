import Foundation
import SwiftUI

struct UndoDialStepAccumulator {
  static let stepAngle = 2.0 * Double.pi / 32.0

  private(set) var angle: Double

  init(angle: Double) {
    self.angle = angle
  }

  mutating func advance(to nextAngle: Double) -> Int {
    var delta = nextAngle - angle
    if delta > Double.pi { delta -= 2 * Double.pi }
    if delta < -Double.pi { delta += 2 * Double.pi }
    let steps = Int(delta / Self.stepAngle)
    guard steps != 0 else { return 0 }
    angle = Self.normalized(angle + Double(steps) * Self.stepAngle)
    return steps
  }

  static func normalized(_ angle: Double) -> Double {
    var value = angle.truncatingRemainder(dividingBy: 2 * Double.pi)
    if value < 0 { value += 2 * Double.pi }
    return value
  }
}

@MainActor
struct UndoDialButton: View {
  let undo: () -> Bool
  let redo: () -> Bool

  @Environment(\.isEnabled) private var isEnabled
  @State private var active = false
  @State private var moved = false
  @State private var accumulator = UndoDialStepAccumulator(angle: 0)
  @State private var indicatorAngle = 0.0
  @State private var indicatorCount = 0

  private let buttonSize = Double(EditorToolRailMetrics.targetSize)

  var body: some View {
    Image(systemName: "arrow.uturn.backward")
      .font(.system(size: 22))
      .frame(width: buttonSize, height: buttonSize)
      .contentShape(Rectangle())
      .foregroundStyle(isEnabled ? NativeTheme.ink : NativeTheme.tertiary)
      .background(Color.clear, in: RoundedRectangle(cornerRadius: 10))
      .overlay {
        if active {
          UndoDialIndicator(
            angle: indicatorAngle,
            count: indicatorCount,
            stepAngle: UndoDialStepAccumulator.stepAngle)
            .frame(width: dialSize, height: dialSize)
            .offset(x: dialOffsetX)
            .allowsHitTesting(false)
        }
      }
      .highPriorityGesture(
        DragGesture(minimumDistance: 0)
          .onChanged(updateDrag)
          .onEnded(endDrag))
      .accessibilityLabel("Undo")
      .accessibilityAddTraits(.isButton)
      .accessibilityAction {
        guard isEnabled else { return }
        _ = undo()
      }
  }

  private var dialSize: Double { 5 * buttonSize }

  private var dialCenter: CGPoint {
    CGPoint(
      x: 1.3 * buttonSize + dialSize / 2,
      y: buttonSize / 2)
  }

  private var dialOffsetX: Double {
    dialCenter.x - buttonSize / 2
  }

  private func angle(_ point: CGPoint) -> Double {
    atan2(point.y - dialCenter.y, point.x - dialCenter.x)
  }

  private func updateDrag(_ value: DragGesture.Value) {
    guard isEnabled else { return }
    if !active {
      active = true
      moved = false
      indicatorCount = 0
      accumulator = UndoDialStepAccumulator(angle: angle(value.startLocation))
      indicatorAngle = accumulator.angle
    }

    let steps = accumulator.advance(to: angle(value.location))
    guard steps != 0 else { return }

    moved = true
    var remaining = steps
    while remaining > 0 {
      guard redo() else { break }
      remaining -= 1
    }
    while remaining < 0 {
      guard undo() else { break }
      remaining += 1
    }
    indicatorAngle = accumulator.angle
    indicatorCount += steps - remaining
  }

  private func endDrag(_ value: DragGesture.Value) {
    guard isEnabled else {
      active = false
      return
    }
    if active, !moved {
      _ = undo()
    }
    active = false
  }
}

private struct UndoDialIndicator: View {
  let angle: Double
  let count: Int
  let stepAngle: Double

  var body: some View {
    Canvas { context, size in
      let scale = min(size.width, size.height) / 83.3
      let center = CGPoint(x: size.width / 2, y: size.height / 2)
      let radius = 40 * scale
      var sweep = UndoDialStepAccumulator.normalized(Double(count) * stepAngle)
      if count == 0 { sweep = 2 * Double.pi }

      if sweep != 0 {
        var sector = Path()
        sector.move(to: center)
        sector.addLine(to: CGPoint(
          x: center.x + radius * cos(angle),
          y: center.y + radius * sin(angle)))
        sector.addArc(
          center: center,
          radius: radius,
          startAngle: .radians(angle),
          endAngle: .radians(angle - sweep),
          clockwise: true)
        sector.closeSubpath()
        context.fill(sector, with: .color(NativeTheme.selectedFill))
      }

      for index in 0..<32 {
        let tickAngle = Double(index) * stepAngle - angle
        var tick = Path()
        tick.move(to: CGPoint(
          x: center.x + 39 * scale * sin(tickAngle),
          y: center.y + 39 * scale * cos(tickAngle)))
        tick.addLine(to: CGPoint(
          x: center.x + 33 * scale * sin(tickAngle),
          y: center.y + 33 * scale * cos(tickAngle)))
        context.stroke(
          tick,
          with: .color(NativeTheme.tertiary),
          style: StrokeStyle(lineWidth: 1.5 * scale, lineCap: .round))
      }
    }
  }
}
