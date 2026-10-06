import SwiftUI

func finalizedTagValues(_ tags: [String], pendingInput: String) -> [String] {
  let pending = pendingInput.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !pending.isEmpty, !tags.contains(pending) else { return tags }
  return tags + [pending]
}

struct EditableTagEditor: View {
  @Binding var tags: [String]
  @Binding var input: String

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if !tags.isEmpty {
        TagWrapLayout(horizontalSpacing: 8, verticalSpacing: 4) {
          ForEach(tags, id: \.self) { tag in
            Button {
              tags.removeAll { $0 == tag }
            } label: {
              HStack(spacing: 8) {
                Text(tag)
                  .lineLimit(1)
                Image(systemName: "xmark")
                  .font(.system(size: 12, weight: .semibold))
              }
              .padding(.horizontal, 10)
              .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Remove tag \(tag)")
            .fixedSize()
          }
        }
      }

      HStack {
        TextField("Add a tag…", text: $input)
          .textInputAutocapitalization(.never)
          .submitLabel(.done)
          .nativeFieldSurface()
          .onSubmit(addPendingTag)
        Button("Add tag", action: addPendingTag)
      }
    }
  }

  private func addPendingTag() {
    tags = finalizedTagValues(tags, pendingInput: input)
    input = ""
  }
}
