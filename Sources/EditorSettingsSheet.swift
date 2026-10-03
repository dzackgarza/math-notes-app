import SwiftUI

@MainActor
struct EditorSettingsSheet: View {
  @Binding var fingerDraws: Bool
  let followLinks: Binding<Bool>?
  @Binding var showTabStrip: Bool
  @Binding var hiddenToolsRaw: String
  let onChooseFolder: (() -> Void)?
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Toggle("Draw with finger", isOn: $fingerDraws)
          if let followLinks {
            Toggle("Follow links", isOn: followLinks)
          }
          Toggle("Show tab strip", isOn: $showTabStrip)
        }

        Section("Toolbar") {
          ForEach(EditorTool.toolbarCases) { tool in
            Toggle(tool.label, isOn: toolVisibility(tool.rawValue))
          }
          Toggle("Drawing mode", isOn: toolVisibility("drawing"))
        }

        if let onChooseFolder {
          Section("Notes folder") {
            Button("Choose notes folder") {
              onChooseFolder()
              dismiss()
            }
          }
        }
      }
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
  }

  private var hiddenTools: Set<String> {
    Set(hiddenToolsRaw.split(separator: ",").map(String.init))
  }

  private func toolVisibility(_ key: String) -> Binding<Bool> {
    Binding(
      get: { !hiddenTools.contains(key) },
      set: { visible in
        var next = hiddenTools
        if visible {
          next.remove(key)
        } else {
          next.insert(key)
        }
        hiddenToolsRaw = next.sorted().joined(separator: ",")
      })
  }
}
