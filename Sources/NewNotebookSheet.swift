import InkEngine
import SwiftUI

struct NewNotebookRequest {
  let title: String
  let parent: FolderReference
  let details: LibraryFolderDetails
}

struct NewNotebookFormState: Equatable {
  static let paperStyles = ["dotted", "grid-medium", "blank", "lined-medium"]
  static let coverColorOrder = ["#24324A", "#5B2328", "#2F4A3A", "#A87B2C"]
  static let coverColors = [
    "#24324A": "Navy",
    "#5B2328": "Oxblood",
    "#2F4A3A": "Forest",
    "#A87B2C": "Ochre",
  ]

  var title = ""
  var description = ""
  var parent: FolderReference
  var paper: String
  var tags: [String]
  var coverColor: String
  var coverStyle: String

  init(
    folders: [FolderReference],
    initialParent: FolderReference?,
    defaults: LibraryFolderDetails
  ) {
    parent = initialParent.flatMap { candidate in
      folders.contains(candidate) ? candidate : nil
    } ?? folders.first ?? FolderReference(path: [])
    paper = defaults.paper
    tags = defaults.tags
    coverColor = defaults.coverColor
    coverStyle = defaults.coverStyle
  }

  var request: NewNotebookRequest {
    NewNotebookRequest(
      title: title,
      parent: parent,
      details: LibraryFolderDetails(
        description: description,
        paper: paper,
        coverColor: coverColor,
        coverStyle: coverStyle,
        tags: tags))
  }
}

@MainActor
struct NewNotebookSheet: View {
  let folders: [FolderReference]
  let knownTags: [LibraryTag]
  let renderPreview: (String, InkPageSize, InkOrientation) throws -> Data
  let onCreate: (NewNotebookRequest) -> Void
  let onCancel: () -> Void

  @State private var form: NewNotebookFormState
  @State private var newTag = ""

  init(
    folders: [FolderReference],
    knownTags: [LibraryTag],
    initialParent: FolderReference? = nil,
    defaults: LibraryFolderDetails,
    renderPreview: @escaping (String, InkPageSize, InkOrientation) throws -> Data,
    onCreate: @escaping (NewNotebookRequest) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.folders = folders
    self.knownTags = knownTags
    self.renderPreview = renderPreview
    self.onCreate = onCreate
    self.onCancel = onCancel
    _form = State(
      initialValue: NewNotebookFormState(
        folders: folders,
        initialParent: initialParent,
        defaults: defaults))
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Notebook") {
          TextField("Notebook title", text: $form.title)
            .textInputAutocapitalization(.sentences)

          TextEditor(text: $form.description)
            .frame(minHeight: 72)
            .onChange(of: form.description) { _, value in
              if value.count > 500 {
                form.description = String(value.prefix(500))
              }
            }
          Text("Description (optional) · \(form.description.count) / 500")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Section("Cover") {
          Picker("Cover style", selection: $form.coverStyle) {
            Text("Classic").tag("classic")
            Text("Spine").tag("spine")
          }
          .pickerStyle(.segmented)

          HStack(spacing: 12) {
            ForEach(NewNotebookFormState.coverColorOrder, id: \.self) { color in
              Button {
                form.coverColor = color
              } label: {
                Circle()
                  .fill(colorValue(color))
                  .frame(width: 30, height: 30)
                  .overlay {
                    if form.coverColor == color {
                      Circle()
                        .stroke(.primary, lineWidth: 2)
                        .padding(-4)
                    }
                  }
              }
              .buttonStyle(.plain)
              .accessibilityLabel(NewNotebookFormState.coverColors[color] ?? color)
              .accessibilityValue(form.coverColor == color ? "Selected" : "")
            }
          }
        }

        Section("Paper") {
          Picker("Paper style", selection: $form.paper) {
            ForEach(NewNotebookFormState.paperStyles, id: \.self) { paper in
              Text(paperLabel(paper)).tag(paper)
            }
          }
          .pickerStyle(.segmented)
        }

        Section("Preview") {
          CreationPaperPreview(
            template: form.paper,
            pageSize: .a4,
            orientation: .portrait,
            render: renderPreview)
            .frame(maxWidth: .infinity)
            .frame(height: 280)
        }

        Section("Tags") {
          ForEach(tagNames, id: \.self) { name in
            Toggle(name, isOn: tagBinding(name))
          }

          HStack {
            TextField("New tag", text: $newTag)
              .textInputAutocapitalization(.never)
              .onSubmit(addTag)
            Button("Add", action: addTag)
              .disabled(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
        }

        Section("Location") {
          Picker("Folder", selection: $form.parent) {
            ForEach(availableFolders) { folder in
              Text(folder.name).tag(folder)
            }
          }
          Text("You can move this notebook later.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .navigationTitle("New Notebook")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: onCancel)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Create") {
            onCreate(form.request)
          }
          .disabled(form.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
  }

  private var availableFolders: [FolderReference] {
    folders.contains(form.parent) ? folders : [form.parent] + folders
  }

  private var tagNames: [String] {
    var result = knownTags.map(\.name)
    for name in form.tags where !result.contains(name) {
      result.append(name)
    }
    return result
  }

  private func tagBinding(_ name: String) -> Binding<Bool> {
    Binding(
      get: { form.tags.contains(name) },
      set: { selected in
        if selected {
          if !form.tags.contains(name) { form.tags.append(name) }
        } else {
          form.tags.removeAll { $0 == name }
        }
      })
  }

  private func addTag() {
    let name = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return }
    if !form.tags.contains(name) { form.tags.append(name) }
    newTag = ""
  }

  private func paperLabel(_ paper: String) -> String {
    switch paper {
    case "dotted": "Dot"
    case "grid-medium": "Grid"
    case "blank": "Plain"
    case "lined-medium": "Lined"
    default: paper.replacingOccurrences(of: "-", with: " ").capitalized
    }
  }

  private func colorValue(_ value: String) -> Color {
    let hex = value.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    guard hex.count == 6, let rgb = UInt64(hex, radix: 16) else { return .secondary }
    return Color(
      red: Double((rgb >> 16) & 0xFF) / 255,
      green: Double((rgb >> 8) & 0xFF) / 255,
      blue: Double(rgb & 0xFF) / 255)
  }
}
