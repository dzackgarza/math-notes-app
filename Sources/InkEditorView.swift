import MJRefresh
import QuartzCore
import SwiftUI
import UIKit

@MainActor
final class InkEditorViewController: UIViewController, UIScrollViewDelegate {
  private let document: EngineDocument
  private let scrollView = UIScrollView()
  private let documentView = UIView()
  private let onEditCommitted: () -> Void
  private let onError: (Error) -> Void
  private lazy var canvasView = InkCanvasView(
    document: document,
    onEditCommitted: onEditCommitted)
  private var documentSize: CGSize
  private var setInitialZoom = false
  private var appliedTool: EditorTool = .pen
  private var documentRevision = 0

  private var pullGate = HeldPullGate()
  private var pullReadyTimer: Timer?
  private var footerWasPulling = false
  private var releasedPullWasArmed = false
  private lazy var addPageFooter = MJRefreshBackNormalFooter(refreshingBlock: { [weak self] in
    self?.completeBottomPull()
  })

  init(
    document: EngineDocument,
    onEditCommitted: @escaping () -> Void = {},
    onError: @escaping (Error) -> Void = { _ in }
  ) {
    self.document = document
    self.onEditCommitted = onEditCommitted
    self.onError = onError
    documentSize = document.contentSize()
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  deinit {
    pullReadyTimer?.invalidate()
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

    configureBottomPull()
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

  func applyHostState(tool: EditorTool, pens: EditorPenSet, revision: Int) {
    loadViewIfNeeded()

    if tool != appliedTool {
      canvasView.applyTool(tool, pens: pens)
      appliedTool = tool
    }

    guard revision != documentRevision else { return }
    documentRevision = revision
    let nextSize = document.contentSize()
    if nextSize != documentSize {
      refreshDocumentGeometry()
    }
  }

  func viewForZooming(in scrollView: UIScrollView) -> UIView? {
    documentView
  }

  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    trackBottomPull()
    syncCanvasTransform()
  }

  func scrollViewDidZoom(_ scrollView: UIScrollView) {
    updateContentInsets()
    syncCanvasTransform()
  }

  func scrollViewWillEndDragging(
    _ scrollView: UIScrollView,
    withVelocity velocity: CGPoint,
    targetContentOffset: UnsafeMutablePointer<CGPoint>
  ) {
    releasedPullWasArmed =
      addPageFooter.state == .pulling &&
      pullGate.release(at: CACurrentMediaTime())
    cancelPullReadyTimer()
  }

  private func configureBottomPull() {
    addPageFooter.setTitle("Pull and hold to add a page", for: .idle)
    addPageFooter.setTitle("Hold to add a page", for: .pulling)
    addPageFooter.setTitle("Adding page…", for: .refreshing)
    scrollView.mj_footer = addPageFooter
  }

  private func trackBottomPull() {
    let pulling = addPageFooter.state == .pulling
    guard pulling != footerWasPulling else { return }
    footerWasPulling = pulling

    if pulling {
      pullGate.becameReady(at: CACurrentMediaTime())
      addPageFooter.setTitle("Hold to add a page", for: .pulling)
      pullReadyTimer = Timer.scheduledTimer(
        withTimeInterval: HeldPullGate.holdDuration,
        repeats: false
      ) { [weak self] _ in
        guard let self, self.addPageFooter.state == .pulling else { return }
        self.addPageFooter.setTitle("Release to add a page", for: .pulling)
      }
      return
    }

    cancelPullReadyTimer()
    if addPageFooter.state != .refreshing {
      pullGate.leftReady()
    }
  }

  private func completeBottomPull() {
    let shouldAdd = releasedPullWasArmed
    releasedPullWasArmed = false
    footerWasPulling = false
    pullGate.leftReady()
    cancelPullReadyTimer()

    guard shouldAdd else {
      addPageFooter.endRefreshing()
      return
    }

    do {
      try document.appendPage()
      refreshDocumentGeometry()
      onEditCommitted()
      addPageFooter.endRefreshing()
      DispatchQueue.main.async { [weak self] in
        self?.scrollToDocumentEnd()
      }
    } catch {
      addPageFooter.endRefreshing()
      onError(error)
    }
  }

  private func cancelPullReadyTimer() {
    pullReadyTimer?.invalidate()
    pullReadyTimer = nil
  }

  private func refreshDocumentGeometry() {
    let zoom = scrollView.zoomScale
    if zoom != 1 {
      scrollView.setZoomScale(1, animated: false)
    }

    documentSize = document.contentSize()
    documentView.frame = CGRect(origin: .zero, size: documentSize)
    scrollView.contentSize = documentSize

    if zoom != 1 {
      scrollView.setZoomScale(zoom, animated: false)
    }
    updateContentInsets()
    syncCanvasTransform()
  }

  private func scrollToDocumentEnd() {
    let minimumY = -scrollView.adjustedContentInset.top
    let maximumY = max(
      minimumY,
      scrollView.contentSize.height - scrollView.bounds.height +
        scrollView.adjustedContentInset.bottom)
    scrollView.setContentOffset(
      CGPoint(x: scrollView.contentOffset.x, y: maximumY),
      animated: true)
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
private struct InkEditorHost: UIViewControllerRepresentable {
  let document: EngineDocument
  let tool: EditorTool
  let revision: Int
  let onEditCommitted: () -> Void
  let onError: (Error) -> Void

  func makeUIViewController(context: Context) -> InkEditorViewController {
    InkEditorViewController(
      document: document,
      onEditCommitted: onEditCommitted,
      onError: onError)
  }

  func updateUIViewController(_ uiViewController: InkEditorViewController, context: Context) {
    uiViewController.applyHostState(
      tool: tool,
      pens: .defaults,
      revision: revision)
  }
}

@MainActor
struct InkEditorView: View {
  let document: EngineDocument
  @Binding var tool: EditorTool
  let onEditCommitted: () -> Void
  let onError: (Error) -> Void

  @State private var documentRevision = 0

  var body: some View {
    ZStack(alignment: .topLeading) {
      InkEditorHost(
        document: document,
        tool: tool,
        revision: documentRevision,
        onEditCommitted: onEditCommitted,
        onError: onError)

      EditorToolRail(
        tool: $tool,
        undo: { history(redo: false) },
        redo: { history(redo: true) })
    }
  }

  private func history(redo: Bool) {
    do {
      let moved: Bool
      if redo {
        moved = try document.redo()
      } else {
        moved = try document.undo()
      }
      guard moved else { return }
      documentRevision &+= 1
      onEditCommitted()
    } catch {
      onError(error)
    }
  }
}
