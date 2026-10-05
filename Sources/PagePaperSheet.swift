import InkEngine
import SwiftUI

private enum PageSizeChoice: String, CaseIterable, Identifiable {
  case a4 = "A4"
  case letter = "Letter"
  case custom = "Custom"

  var id: Self { self }

  var engineValue: InkPageSize {
    switch self {
    case .a4: INK_PAGE_A4
    case .letter: INK_PAGE_LETTER
    case .custom: INK_PAGE_CUSTOM
    }
  }

  init(_ value: InkPageSize) {
    switch value {
    case INK_PAGE_A4: self = .a4
    case INK_PAGE_LETTER: self = .letter
    default: self = .custom
    }
  }
}

private enum PageOrientationChoice: String, CaseIterable, Identifiable {
  case portrait = "Portrait"
  case landscape = "Landscape"

  var id: Self { self }

  var engineValue: InkOrientation {
    switch self {
    case .portrait: INK_PORTRAIT
    case .landscape: INK_LANDSCAPE
    }
  }

  init(_ value: InkOrientation) {
    self = value == INK_LANDSCAPE ? .landscape : .portrait
  }
}

struct PagePaperRequest: Identifiable {
  let id = UUID()
  let templates: [String]
  let template: String?
  let pageSize: EnginePageSize
}

struct PagePaperSheet: View {
  let request: PagePaperRequest
  let onTemplate: (String) -> Void
  let onPageSize: (InkPageSize, InkOrientation, Double, Double) -> Void
  let onDone: () -> Void

  @State private var selectedTemplate: String?
  @State private var size: PageSizeChoice
  @State private var orientation: PageOrientationChoice

  init(
    request: PagePaperRequest,
    onTemplate: @escaping (String) -> Void,
    onPageSize: @escaping (InkPageSize, InkOrientation, Double, Double) -> Void,
    onDone: @escaping () -> Void
  ) {
    self.request = request
    self.onTemplate = onTemplate
    self.onPageSize = onPageSize
    self.onDone = onDone
    _selectedTemplate = State(initialValue: request.template)
    _size = State(initialValue: PageSizeChoice(request.pageSize.size))
    _orientation = State(initialValue: PageOrientationChoice(request.pageSize.orientation))
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Paper style") {
          ForEach(request.templates, id: \.self) { template in
            Button {
              selectedTemplate = template
              onTemplate(template)
            } label: {
              HStack {
                Text(Self.displayLabel(template))
                  .foregroundStyle(.primary)
                Spacer()
                if selectedTemplate == template {
                  Image(systemName: "checkmark")
                }
              }
            }
          }
        }

        Section("Page size") {
          Picker("Page size", selection: $size) {
            Text("A4").tag(PageSizeChoice.a4)
            Text("Letter").tag(PageSizeChoice.letter)
            if size == .custom {
              Text("Custom").tag(PageSizeChoice.custom)
            }
          }
          .pickerStyle(.segmented)
          .onChange(of: size) { _, value in
            apply(size: value, orientation: orientation)
          }

          if size == .custom {
            Text(
              "Custom: \(Int(request.pageSize.width.rounded())) × \(Int(request.pageSize.height.rounded())) pt")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        Section("Orientation") {
          Picker("Orientation", selection: $orientation) {
            ForEach(PageOrientationChoice.allCases) { value in
              Text(value.rawValue).tag(value)
            }
          }
          .pickerStyle(.segmented)
          .onChange(of: orientation) { _, value in
            apply(size: size, orientation: value)
          }
        }
      }
      .navigationTitle("Paper for new pages")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done", action: onDone)
        }
      }
    }
  }

  private func apply(size: PageSizeChoice, orientation: PageOrientationChoice) {
    onPageSize(
      size.engineValue,
      orientation.engineValue,
      request.pageSize.width,
      request.pageSize.height)
  }

  static func displayLabel(_ template: String) -> String {
    switch template {
    case "blank": "Plain paper"
    case "dotted": "Dot paper"
    case "lined-medium": "Lined paper"
    case "grid-medium": "Grid paper"
    case "grid-fine": "Graph paper"
    case "lined-wide": "Lined paper, wide"
    case "lined-narrow": "Lined paper, narrow"
    case "grid-coarse": "Grid paper, coarse"
    default: template
    }
  }

  static func sortedTemplates(_ templates: [String]) -> [String] {
    templates.sorted { displayLabel($0) < displayLabel($1) }
  }
}
