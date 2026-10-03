import SwiftUI

struct LibraryTagSheet: View {
  let onAdd: (String, String) -> Void
  let onCancel: () -> Void

  @State private var name = ""
  @State private var color = LibraryMetadataFile.tagColors[0]

  var body: some View {
    NavigationStack {
      Form {
        Section("Tag") {
          TextField("Tag name", text: $name)
            .textInputAutocapitalization(.never)
        }

        Section("Color") {
          HStack(spacing: 10) {
            ForEach(LibraryMetadataFile.tagColors, id: \.self) { value in
              Button {
                color = value
              } label: {
                Circle()
                  .fill(colorValue(value))
                  .frame(width: 28, height: 28)
                  .overlay {
                    if color == value {
                      Circle()
                        .stroke(.primary, lineWidth: 2)
                        .padding(-4)
                    }
                  }
              }
              .buttonStyle(.plain)
              .accessibilityLabel(value)
              .accessibilityValue(color == value ? "Selected" : "")
            }
          }
        }
      }
      .navigationTitle("New Tag")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: onCancel)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Add Tag") {
            onAdd(name.trimmingCharacters(in: .whitespacesAndNewlines), color)
          }
          .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
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
