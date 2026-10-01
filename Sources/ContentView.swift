import SwiftUI

@MainActor
struct ContentView: View {
  @State private var document = EngineDocument()

  var body: some View {
    NavigationStack {
      InkEditorView(document: document)
        .navigationTitle("Math Notes")
        .navigationBarTitleDisplayMode(.inline)
    }
  }
}
