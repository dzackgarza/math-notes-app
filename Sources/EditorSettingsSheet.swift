import SwiftUI

@MainActor
struct EditorSettingsSheet: View {
  @Binding var fingerDraws: Bool
  let followLinks: Binding<Bool>?
  @Binding var showTabStrip: Bool
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
}
