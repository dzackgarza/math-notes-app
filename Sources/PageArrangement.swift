import InkEngine

enum EditorPageArrangement: Int, CaseIterable, Identifiable {
  case vertical = 0
  case horizontal = 1
  case twoPage = 2

  var id: Self { self }

  var label: String {
    switch self {
    case .vertical: "Vertical Scroll"
    case .horizontal: "Horizontal Scroll"
    case .twoPage: "Two Pages"
    }
  }

  var systemImage: String {
    switch self {
    case .vertical: "rectangle.stack"
    case .horizontal: "rectangle.split.3x1"
    case .twoPage: "rectangle.split.2x1"
    }
  }

  var engineValue: InkPageArrangement {
    switch self {
    case .vertical: INK_PAGES_VERTICAL
    case .horizontal: INK_PAGES_HORIZONTAL
    case .twoPage: INK_PAGES_TWO_PAGE
    }
  }

  static func stored(_ rawValue: Int) -> EditorPageArrangement {
    EditorPageArrangement(rawValue: rawValue) ?? .vertical
  }
}
