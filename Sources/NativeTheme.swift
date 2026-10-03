import SwiftUI
import UIKit

enum NativeTheme {
  static let interfaceRegularName = "AlegreyaSans-Regular"
  static let interfaceMediumName = "AlegreyaSans-Medium"
  static let interfaceExtraBoldName = "AlegreyaSans-ExtraBold"
  static let volumeFontName = "Alegreya-Regular"

  static let board = color("#DADDD5")
  static let leaf = color("#EEF0EA")
  static let ink = color("#1C2430")
  static let graphite = color("#555D67")
  static let ribbon = color("#9E2A2B")
  static let paper = color("#FBFAF6")
  static let warning = color("#7A4E00")
  static let separator = ink.opacity(0.16)

  static let boardUI = uiColor("#DADDD5")
  static let leafUI = uiColor("#EEF0EA")
  static let inkUI = uiColor("#1C2430")
  static let graphiteUI = uiColor("#555D67")
  static let ribbonUI = uiColor("#9E2A2B")
  static let paperUI = uiColor("#FBFAF6")

  static let footnote = Font.custom(interfaceRegularName, size: 14)
  static let callout = Font.custom(interfaceRegularName, size: 16)
  static let subhead = Font.custom(interfaceExtraBoldName, size: 16)
  static let body = Font.custom(interfaceRegularName, size: 18)
  static let headline = Font.custom(interfaceExtraBoldName, size: 18)
  static let title = Font.custom(interfaceExtraBoldName, size: 24)
  static let largeTitle = Font.custom(interfaceExtraBoldName, size: 32)
  static let spineTitle = Font.custom(volumeFontName, size: 15).weight(.bold)
  static let volumeTitle = Font.custom(volumeFontName, size: 32).weight(.heavy)

  static func uiColor(_ value: String) -> UIColor {
    let hex = value.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    guard hex.count == 6, let rgb = UInt64(hex, radix: 16) else { return graphiteUI }
    return UIColor(
      red: CGFloat((rgb >> 16) & 0xFF) / 255,
      green: CGFloat((rgb >> 8) & 0xFF) / 255,
      blue: CGFloat(rgb & 0xFF) / 255,
      alpha: 1)
  }

  static func color(_ value: String) -> Color {
    let hex = value.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    guard hex.count == 6, let rgb = UInt64(hex, radix: 16) else { return graphite }
    return Color(
      red: Double((rgb >> 16) & 0xFF) / 255,
      green: Double((rgb >> 8) & 0xFF) / 255,
      blue: Double(rgb & 0xFF) / 255)
  }
}

private struct NativeFieldSurface: ViewModifier {
  func body(content: Content) -> some View {
    content
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .background(NativeTheme.paper, in: RoundedRectangle(cornerRadius: 8))
      .overlay {
        RoundedRectangle(cornerRadius: 8)
          .stroke(NativeTheme.separator, lineWidth: 1)
      }
  }
}

extension View {
  func nativeFieldSurface() -> some View {
    modifier(NativeFieldSurface())
  }
}

extension View {
  func nativePopoverSurface() -> some View {
    foregroundStyle(NativeTheme.ink)
      .font(NativeTheme.body)
      .tint(NativeTheme.ink)
      .presentationBackground(NativeTheme.leaf)
  }
}
