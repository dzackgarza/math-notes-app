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
          .font(NativeTheme.headline)
          .frame(maxWidth: .infinity, alignment: .leading)

        HStack {
          Text("Current file")
            .frame(maxWidth: .infinity)
          Text("Conflict copy")
            .frame(maxWidth: .infinity)
        }
        .font(NativeTheme.subhead)

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
          if request.conflict.page
            && request.conflict.originalBytes != nil
          {
            Button("Keep both pages") {
              onChoice(.both)
            }
            .buttonStyle(.borderedProminent)
          }
        }
      }
      .padding(16)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .nativeSheetSurface()
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

  func makeUIView(context: Context) -> UIStackView {
    let stack = UIStackView()
    stack.axis = .horizontal
    stack.spacing = 12
    stack.distribution = .fillEqually

    let leftImage = left.flatMap(UIImage.init(data:))
    let rightImage = right.flatMap(UIImage.init(data:))
    let synchronized = leftImage != nil && rightImage != nil
    let leftPane = pane(image: leftImage, summary: leftSummary)
    let rightPane = pane(image: rightImage, summary: rightSummary)
    stack.addArrangedSubview(leftPane.scroll)
    stack.addArrangedSubview(rightPane.scroll)
    context.coordinator.install(
      left: leftPane,
      right: rightPane,
      synchronized: synchronized)
    return stack
  }

  func updateUIView(_ stack: UIStackView, context: Context) {}

  private func pane(
    image: UIImage?,
    summary: String
  ) -> Coordinator.Pane {
    let scroll = UIScrollView()
    scroll.minimumZoomScale = 1
    scroll.maximumZoomScale = image == nil ? 1 : 5
    scroll.bouncesZoom = image != nil
    scroll.backgroundColor = NativeTheme.leafUI
    scroll.layer.cornerRadius = 10
    scroll.clipsToBounds = true

    let content = UIView()
    content.translatesAutoresizingMaskIntoConstraints = false
    scroll.addSubview(content)
    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
      content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
      content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
      content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
      content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
      content.heightAnchor.constraint(greaterThanOrEqualTo: scroll.frameLayoutGuide.heightAnchor),
    ])

    if let image {
      content.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor).isActive = true
      let view = UIImageView(image: image)
      view.contentMode = .scaleAspectFit
      view.translatesAutoresizingMaskIntoConstraints = false
      content.addSubview(view)
      NSLayoutConstraint.activate([
        view.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
        view.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
        view.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
        view.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),
      ])
    } else {
      let label = UILabel()
      label.text = summary
      label.numberOfLines = 0
      label.font = UIFont(name: NativeTheme.interfaceRegularName, size: 18)
        ?? .preferredFont(forTextStyle: .body)
      label.textColor = NativeTheme.inkUI
      label.translatesAutoresizingMaskIntoConstraints = false
      content.addSubview(label)
      NSLayoutConstraint.activate([
        label.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
        label.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
        label.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
        label.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
      ])
    }
    return Coordinator.Pane(scroll: scroll, content: content)
  }

  final class Coordinator: NSObject, UIScrollViewDelegate {
    struct Pane {
      let scroll: UIScrollView
      let content: UIView
    }

    private var left: Pane?
    private var right: Pane?
    private var synchronized = false
    private var applyingSync = false

    func install(left: Pane, right: Pane, synchronized: Bool) {
      self.left = left
      self.right = right
      self.synchronized = synchronized
      left.scroll.delegate = self
      right.scroll.delegate = self
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
      pane(for: scrollView)?.content
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
      synchronize(from: scrollView)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
      synchronize(from: scrollView)
    }

    private func pane(for scrollView: UIScrollView) -> Pane? {
      if left?.scroll === scrollView { return left }
      if right?.scroll === scrollView { return right }
      return nil
    }

    private func other(than scrollView: UIScrollView) -> UIScrollView? {
      if left?.scroll === scrollView { return right?.scroll }
      if right?.scroll === scrollView { return left?.scroll }
      return nil
    }

    private func synchronize(from source: UIScrollView) {
      guard synchronized, !applyingSync, let target = other(than: source) else { return }
      applyingSync = true
      target.setZoomScale(source.zoomScale, animated: false)
      target.contentOffset = source.contentOffset
      applyingSync = false
    }
  }
}
