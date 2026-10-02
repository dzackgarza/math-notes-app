import SwiftUI
import UIKit

struct ConflictReviewRequest: Identifiable {
  let reference: NotebookReference
  let conflict: NotebookConflict

  var id: String { reference.id + ":" + conflict.id }
}

@MainActor
struct ConflictReviewSheet: View {
  let request: ConflictReviewRequest
  let onChoice: (NotebookConflictChoice) -> Void
  let onCancel: () -> Void

  var body: some View {
    NavigationStack {
      VStack(spacing: 12) {
        Text("\(request.conflict.provider): \(request.conflict.original)")
          .font(.headline)
          .frame(maxWidth: .infinity, alignment: .leading)

        HStack {
          Text("Current file")
            .frame(maxWidth: .infinity)
          Text("Conflict copy")
            .frame(maxWidth: .infinity)
        }
        .font(.subheadline.weight(.semibold))

        ConflictComparisonView(
          left: request.conflict.left,
          leftSummary: request.conflict.leftSummary,
          right: request.conflict.right,
          rightSummary: request.conflict.rightSummary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)

        HStack(spacing: 12) {
          Button("Cancel", action: onCancel)
          Spacer()
          Button(
            request.conflict.originalBytes == nil
              ? "Keep deletion"
              : "Keep current file"
          ) {
            onChoice(.original)
          }
          Button(
            request.conflict.originalBytes == nil
              ? "Restore conflict copy"
              : "Keep conflict copy"
          ) {
            onChoice(.copy)
          }
          if request.conflict.page && request.conflict.originalBytes != nil {
            Button("Keep both pages") {
              onChoice(.both)
            }
            .buttonStyle(.borderedProminent)
          }
        }
      }
      .padding(16)
      .navigationTitle("Compare conflicting versions")
      .navigationBarTitleDisplayMode(.inline)
    }
    .interactiveDismissDisabled(true)
  }
}

@MainActor
private struct ConflictComparisonView: UIViewRepresentable {
  let left: Data?
  let leftSummary: String
  let right: Data?
  let rightSummary: String

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeUIView(context: Context) -> UIScrollView {
    let scroll = UIScrollView()
    scroll.minimumZoomScale = 1
    scroll.maximumZoomScale = 5
    scroll.bouncesZoom = true
    scroll.delegate = context.coordinator

    let content = UIStackView()
    content.axis = .horizontal
    content.spacing = 12
    content.distribution = .fillEqually
    content.translatesAutoresizingMaskIntoConstraints = false
    scroll.addSubview(content)
    context.coordinator.content = content

    content.addArrangedSubview(pane(image: left, summary: leftSummary))
    content.addArrangedSubview(pane(image: right, summary: rightSummary))

    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
      content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
      content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
      content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
      content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
      content.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
    ])
    return scroll
  }

  func updateUIView(_ scroll: UIScrollView, context: Context) {}

  private func pane(image: Data?, summary: String) -> UIView {
    let container = UIView()
    container.backgroundColor = .secondarySystemBackground
    container.layer.cornerRadius = 10
    container.clipsToBounds = true

    if let image, let uiImage = UIImage(data: image) {
      let view = UIImageView(image: uiImage)
      view.contentMode = .scaleAspectFit
      view.translatesAutoresizingMaskIntoConstraints = false
      container.addSubview(view)
      NSLayoutConstraint.activate([
        view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
        view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
        view.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
        view.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
      ])
    } else {
      let label = UILabel()
      label.text = summary
      label.numberOfLines = 0
      label.font = .preferredFont(forTextStyle: .body)
      label.textColor = .label
      label.translatesAutoresizingMaskIntoConstraints = false
      container.addSubview(label)
      NSLayoutConstraint.activate([
        label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
        label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
        label.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
        label.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -16),
      ])
    }
    return container
  }

  final class Coordinator: NSObject, UIScrollViewDelegate {
    weak var content: UIView?

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
      content
    }
  }
}
