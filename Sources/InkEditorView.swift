import SwiftUI
import UIKit

@MainActor
final class InkEditorViewController: UIViewController, UIScrollViewDelegate {
  private let document: EngineDocument
  private let scrollView = UIScrollView()
  private let documentView = UIView()
  private let onEditCommitted: () -> Void
  private lazy var canvasView = InkCanvasView(
    document: document,
    onEditCommitted: onEditCommitted)
  private let documentSize: CGSize
  private var setInitialZoom = false

  init(document: EngineDocument, onEditCommitted: @escaping () -> Void = {}) {
    self.document = document
    self.onEditCommitted = onEditCommitted
    documentSize = document.contentSize()
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    view.backgroundColor = .systemGroupedBackground

    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.delegate = self
    scrollView.alwaysBounceVertical = true
    scrollView.alwaysBounceHorizontal = true
    scrollView.bouncesZoom = true
    scrollView.minimumZoomScale = 0.5
    scrollView.maximumZoomScale = 4
    scrollView.contentInsetAdjustmentBehavior = .never
    scrollView.delaysContentTouches = false
    scrollView.panGestureRecognizer.allowedTouchTypes = [
      NSNumber(value: UITouch.TouchType.direct.rawValue)
    ]
    scrollView.pinchGestureRecognizer?.allowedTouchTypes = [
      NSNumber(value: UITouch.TouchType.direct.rawValue)
    ]

    view.addSubview(scrollView)
    NSLayoutConstraint.activate([
      scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      scrollView.topAnchor.constraint(equalTo: view.topAnchor),
      scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])

    documentView.frame = CGRect(origin: .zero, size: documentSize)
    documentView.backgroundColor = .clear
    documentView.isUserInteractionEnabled = false
    scrollView.addSubview(documentView)
    scrollView.contentSize = documentSize

    canvasView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.addSubview(canvasView)
    NSLayoutConstraint.activate([
      canvasView.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor),
      canvasView.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor),
      canvasView.topAnchor.constraint(equalTo: scrollView.frameLayoutGuide.topAnchor),
      canvasView.bottomAnchor.constraint(equalTo: scrollView.frameLayoutGuide.bottomAnchor),
    ])
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()

    if !setInitialZoom, scrollView.bounds.width > 0, documentSize.width > 0 {
      let fitWidth = max(0.5, (scrollView.bounds.width - 32) / documentSize.width)
      scrollView.zoomScale = min(fitWidth, scrollView.maximumZoomScale)
      setInitialZoom = true
    }

    updateContentInsets()
    syncCanvasTransform()
  }

  func viewForZooming(in scrollView: UIScrollView) -> UIView? {
    documentView
  }

  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    syncCanvasTransform()
  }

  func scrollViewDidZoom(_ scrollView: UIScrollView) {
    updateContentInsets()
    syncCanvasTransform()
  }

  private func updateContentInsets() {
    let scaledWidth = documentSize.width * scrollView.zoomScale
    let scaledHeight = documentSize.height * scrollView.zoomScale
    let horizontal = max(0, (scrollView.bounds.width - scaledWidth) / 2)
    let vertical = max(0, (scrollView.bounds.height - scaledHeight) / 2)
    let inset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    if scrollView.contentInset != inset {
      scrollView.contentInset = inset
    }
  }

  private func syncCanvasTransform() {
    guard canvasView.bounds.width > 0, canvasView.bounds.height > 0 else { return }

    let origin = documentView.convert(.zero, to: canvasView)
    let xUnit = documentView.convert(CGPoint(x: 1, y: 0), to: canvasView)
    let yUnit = documentView.convert(CGPoint(x: 0, y: 1), to: canvasView)
    canvasView.setViewTransform(
      CGAffineTransform(
        a: xUnit.x - origin.x,
        b: xUnit.y - origin.y,
        c: yUnit.x - origin.x,
        d: yUnit.y - origin.y,
        tx: origin.x,
        ty: origin.y))
  }
}

@MainActor
struct InkEditorView: UIViewControllerRepresentable {
  let document: EngineDocument
  let onEditCommitted: () -> Void

  init(document: EngineDocument, onEditCommitted: @escaping () -> Void = {}) {
    self.document = document
    self.onEditCommitted = onEditCommitted
  }

  func makeUIViewController(context: Context) -> InkEditorViewController {
    InkEditorViewController(document: document, onEditCommitted: onEditCommitted)
  }

  func updateUIViewController(_ uiViewController: InkEditorViewController, context: Context) {}
}
