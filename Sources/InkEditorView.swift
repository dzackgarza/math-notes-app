import MJRefresh
import QuartzCore
import SwiftUI
import UIKit

enum EditorPageCommand: Equatable {
  case select(Int)
  case clear(Int)
  case requestTextAtCenter
  case commitText(EditorTextRequest, EngineTextProperties)
  case pasteSVGAtCenter(String)
}

@MainActor
final class InkEditorViewController: UIViewController, UIScrollViewDelegate, UIContextMenuInteractionDelegate {
  private let document: EngineDocument
  private let scrollView = UIScrollView()
  private let documentView = UIView()
  private let onEditCommitted: () -> Void
  private let onCurrentPageChanged: (Int) -> Void
  private let onPageCommandHandled: () -> Void
  private let onTextRequested: (EditorTextRequest) -> Void
  private let onError: (Error) -> Void
  private lazy var canvasView = InkCanvasView(
    document: document,
    onInteractionEnded: { [weak self] in self?.canvasInteractionEnded() })
  private let selectionBar = UIStackView()
  private var documentSize: CGSize
  private var setInitialZoom = false
  private var appliedTool: EditorTool = .pen
  private var appliedEraserMode: EditorEraserMode = .stroke
  private var appliedSelectorMode: EditorSelectorMode = .freehand
  private var appliedSpaceMode: EditorSpaceMode = .reflow
  private var appliedPens = EditorPenSet.defaults
  private var appliedArrangement = EditorPageArrangement.vertical
  private var appliedLayerID: String?
  private var documentRevision = 0
  private var pageNavigationRevision = 0
  private var fitRevision = 0
  private var appliedPageCommand: EditorPageCommand?
  private var reportedPage = -1

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
    onCurrentPageChanged: @escaping (Int) -> Void = { _ in },
    onPageCommandHandled: @escaping () -> Void = {},
    onTextRequested: @escaping (EditorTextRequest) -> Void = { _ in },
    onError: @escaping (Error) -> Void = { _ in }
  ) {
    self.document = document
    self.onEditCommitted = onEditCommitted
    self.onCurrentPageChanged = onCurrentPageChanged
    self.onPageCommandHandled = onPageCommandHandled
    self.onTextRequested = onTextRequested
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
    scrollView.minimumZoomScale = 0.25
    scrollView.maximumZoomScale = 8
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
    configureSelectionBar()
    canvasView.addInteraction(UIContextMenuInteraction(delegate: self))
    let textTap = UITapGestureRecognizer(target: self, action: #selector(handleTextTap))
    textTap.cancelsTouchesInView = false
    textTap.allowedTouchTypes = [
      NSNumber(value: UITouch.TouchType.direct.rawValue),
      NSNumber(value: UITouch.TouchType.pencil.rawValue),
    ]
    canvasView.addGestureRecognizer(textTap)
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()

    if !setInitialZoom,
      scrollView.bounds.width > 0,
      scrollView.bounds.height > 0,
      documentSize.width > 0,
      documentSize.height > 0
    {
      fitPages(animated: false)
      setInitialZoom = true
    }

    updateContentInsets()
    syncCanvasTransform()
    refreshSelectionBar()
  }

  func applyHostState(
    tool: EditorTool,
    eraserMode: EditorEraserMode,
    selectorMode: EditorSelectorMode,
    spaceMode: EditorSpaceMode,
    pens: EditorPenSet,
    revision: Int,
    arrangement: EditorPageArrangement,
    activeLayerID: String?,
    fitRevision: Int,
    targetPage: Int,
    navigationRevision: Int,
    pageCommand: EditorPageCommand?
  ) {
    loadViewIfNeeded()

    if tool != appliedTool || eraserMode != appliedEraserMode || selectorMode != appliedSelectorMode || spaceMode != appliedSpaceMode || pens != appliedPens {
      canvasView.applyTool(
        tool,
        pens: pens,
        eraserMode: eraserMode,
        selectorMode: selectorMode,
        spaceMode: spaceMode)
      appliedTool = tool
      appliedEraserMode = eraserMode
      appliedSelectorMode = selectorMode
      appliedSpaceMode = spaceMode
      appliedPens = pens
    }
    canvasView.setDrawingSuppressed(tool == .text)

    if arrangement != appliedArrangement {
      do {
        try document.setArrangement(arrangement.engineValue)
        appliedArrangement = arrangement
        setInitialZoom = false
        refreshDocumentGeometry()
        view.setNeedsLayout()
        view.layoutIfNeeded()
        scrollToPage(targetPage)
      } catch {
        onError(error)
      }
    }

    if activeLayerID != appliedLayerID {
      appliedLayerID = activeLayerID
      if let activeLayerID {
        do {
          let layers = try document.layers()
          guard let index = layers.firstIndex(where: { $0.id == activeLayerID }) else {
            throw EngineDocumentError.operation("Set active layer", "layer no longer exists")
          }
          try canvasView.setLayer(index)
        } catch {
          onError(error)
        }
      }
    }

    if fitRevision != self.fitRevision {
      self.fitRevision = fitRevision
      fitPages(animated: true)
    }

    if revision != documentRevision {
      documentRevision = revision
      let nextSize = document.contentSize()
      if nextSize != documentSize {
        refreshDocumentGeometry()
      }
      refreshSelectionBar()
    }

    if navigationRevision != pageNavigationRevision {
      pageNavigationRevision = navigationRevision
      scrollToPage(targetPage)
    }

    if pageCommand != appliedPageCommand {
      appliedPageCommand = pageCommand
      if let pageCommand {
        handlePageCommand(pageCommand)
      }
    }
  }

  func viewForZooming(in scrollView: UIScrollView) -> UIView? {
    documentView
  }

  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    trackBottomPull()
    syncCanvasTransform()
    refreshSelectionBar()
  }

  func scrollViewDidZoom(_ scrollView: UIScrollView) {
    updateContentInsets()
    syncCanvasTransform()
    refreshSelectionBar()
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

  func contextMenuInteraction(
    _ interaction: UIContextMenuInteraction,
    configurationForMenuAtLocation location: CGPoint
  ) -> UIContextMenuConfiguration? {
    guard let svg = UIPasteboard.general.string, !svg.isEmpty else { return nil }
    return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
      let paste = UIAction(
        title: "Paste",
        image: UIImage(systemName: "doc.on.clipboard")
      ) { [weak self] _ in
        self?.paste(svg, at: location)
      }
      return UIMenu(children: [paste])
    }
  }

  private func configureSelectionBar() {
    selectionBar.axis = .horizontal
    selectionBar.spacing = 2
    selectionBar.isLayoutMarginsRelativeArrangement = true
    selectionBar.directionalLayoutMargins = NSDirectionalEdgeInsets(
      top: 2, leading: 2, bottom: 2, trailing: 2)
    selectionBar.backgroundColor = .secondarySystemBackground
    selectionBar.layer.cornerRadius = 12
    selectionBar.layer.shadowColor = UIColor.black.cgColor
    selectionBar.layer.shadowOpacity = 0.12
    selectionBar.layer.shadowRadius = 8
    selectionBar.layer.shadowOffset = CGSize(width: 0, height: 3)
    selectionBar.isHidden = true

    selectionBar.addArrangedSubview(selectionButton(
      label: "Copy", systemImage: "doc.on.doc", action: #selector(copySelection)))
    selectionBar.addArrangedSubview(selectionButton(
      label: "Cut", systemImage: "scissors", action: #selector(cutSelection)))
    selectionBar.addArrangedSubview(selectionButton(
      label: "Duplicate", systemImage: "plus.square.on.square", action: #selector(duplicateSelection)))
    selectionBar.addArrangedSubview(selectionButton(
      label: "Delete selection", systemImage: "trash", action: #selector(deleteSelection)))
    view.addSubview(selectionBar)
  }

  private func selectionButton(label: String, systemImage: String, action: Selector) -> UIButton {
    let button = UIButton(type: .system)
    button.setImage(UIImage(systemName: systemImage), for: .normal)
    button.accessibilityLabel = label
    button.addTarget(self, action: action, for: .touchUpInside)
    button.widthAnchor.constraint(equalToConstant: 44).isActive = true
    button.heightAnchor.constraint(equalToConstant: 44).isActive = true
    return button
  }

  private func canvasInteractionEnded() {
    onEditCommitted()
    refreshSelectionBar()
  }

  private func refreshSelectionBar() {
    guard isViewLoaded, let selection = canvasView.selectionFrame() else {
      selectionBar.isHidden = true
      return
    }

    selectionBar.isHidden = false
    let target = canvasView.convert(selection, to: view)
    let size = selectionBar.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
    let safe = view.safeAreaLayoutGuide.layoutFrame
    let minimumX = safe.minX + 8
    let maximumX = max(minimumX, safe.maxX - size.width - 8)
    let x = min(max(target.midX - size.width / 2, minimumX), maximumX)
    var y = target.minY - size.height - 8
    if y < safe.minY + 8 {
      y = min(target.maxY + 8, safe.maxY - size.height - 8)
    }
    selectionBar.frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
  }

  @objc private func copySelection() {
    do {
      guard let svg = try canvasView.copySelection() else { return }
      UIPasteboard.general.string = svg
    } catch {
      onError(error)
    }
  }

  @objc private func cutSelection() {
    do {
      guard let svg = try canvasView.copySelection() else { return }
      UIPasteboard.general.string = svg
      try canvasView.deleteSelection()
      onEditCommitted()
      refreshSelectionBar()
    } catch {
      onError(error)
    }
  }

  @objc private func duplicateSelection() {
    do {
      try canvasView.duplicateSelection()
      onEditCommitted()
      refreshSelectionBar()
    } catch {
      onError(error)
    }
  }

  @objc private func deleteSelection() {
    do {
      try canvasView.deleteSelection()
      onEditCommitted()
      refreshSelectionBar()
    } catch {
      onError(error)
    }
  }

  private func handlePageCommand(_ command: EditorPageCommand) {
    defer { onPageCommandHandled() }
    do {
      switch command {
      case let .select(page):
        try canvasView.selectAll(page: page)
      case let .clear(page):
        try canvasView.selectAll(page: page)
        try canvasView.deleteSelection()
        onEditCommitted()
      case .requestTextAtCenter:
        requestText(
          at: CGPoint(
            x: canvasView.bounds.midX,
            y: canvasView.bounds.midY))
      case let .commitText(request, properties):
        if properties.content.isEmpty {
          if request.existing {
            try canvasView.deleteSelection()
            onEditCommitted()
          }
        } else {
          try canvasView.editText(
            properties,
            at: request.point,
            existing: request.existing)
          onEditCommitted()
        }
      case let .pasteSVGAtCenter(svg):
        try canvasView.paste(
          svg,
          at: CGPoint(
            x: canvasView.bounds.midX,
            y: canvasView.bounds.midY))
        onEditCommitted()
      }
      refreshSelectionBar()
    } catch {
      onError(error)
    }
  }

  @objc private func handleTextTap(_ recognizer: UITapGestureRecognizer) {
    guard appliedTool == .text, recognizer.state == .ended else { return }
    requestText(at: recognizer.location(in: canvasView))
  }

  private func requestText(at point: CGPoint) {
    do {
      let existing = try canvasView.selectText(at: point)
      let properties = existing
        ? try canvasView.textProperties()
        : EngineTextProperties(content: "", width: 300, rtl: false)
      refreshSelectionBar()
      onTextRequested(
        EditorTextRequest(
          point: point,
          existing: existing,
          properties: properties))
    } catch {
      onError(error)
    }
  }

  private func paste(_ svg: String, at point: CGPoint) {
    do {
      try canvasView.paste(svg, at: point)
      onEditCommitted()
      refreshSelectionBar()
    } catch {
      onError(error)
    }
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

  private func fitPages(animated: Bool) {
    guard scrollView.bounds.width > 0,
      scrollView.bounds.height > 0,
      documentSize.width > 0,
      documentSize.height > 0
    else { return }

    let fit: CGFloat
    if appliedArrangement == .horizontal {
      fit = max(1, scrollView.bounds.height - 32) / documentSize.height
    } else {
      fit = max(1, scrollView.bounds.width - 32) / documentSize.width
    }
    scrollView.setZoomScale(
      min(max(fit, scrollView.minimumZoomScale), scrollView.maximumZoomScale),
      animated: animated)
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
  private func scrollToPage(_ index: Int) {
    do {
      let page = try document.pageRect(index: index)
      let zoom = scrollView.zoomScale
      let inset = scrollView.adjustedContentInset
      let minimumX = -inset.left
      let minimumY = -inset.top
      let maximumX = max(minimumX, documentSize.width * zoom - scrollView.bounds.width + inset.right)
      let maximumY = max(minimumY, documentSize.height * zoom - scrollView.bounds.height + inset.bottom)
      let x = min(max(page.midX * zoom - scrollView.bounds.width / 2, minimumX), maximumX)
      let y = min(max(page.midY * zoom - scrollView.bounds.height / 2, minimumY), maximumY)
      scrollView.setContentOffset(CGPoint(x: x, y: y), animated: true)
    } catch {
      onError(error)
    }
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

    let origin = documentView.convert(CGPoint.zero, to: canvasView)
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
    updateCurrentPage()
  }

  private func updateCurrentPage() {
    let center = CGPoint(x: canvasView.bounds.midX, y: canvasView.bounds.midY)
    guard let page = canvasView.page(at: center), page != reportedPage else { return }
    reportedPage = page
    DispatchQueue.main.async { [onCurrentPageChanged] in
      onCurrentPageChanged(page)
    }
  }
}

@MainActor
private struct InkEditorHost: UIViewControllerRepresentable {
  let document: EngineDocument
  let eraserMode: EditorEraserMode
  let selectorMode: EditorSelectorMode
  let spaceMode: EditorSpaceMode
  let tool: EditorTool
  let pens: EditorPenSet
  let arrangement: EditorPageArrangement
  let activeLayerID: String?
  let fitRevision: Int
  let revision: Int
  let targetPage: Int
  let navigationRevision: Int
  let pageCommand: EditorPageCommand?
  let onEditCommitted: () -> Void
  let onCurrentPageChanged: (Int) -> Void
  let onPageCommandHandled: () -> Void
  let onTextRequested: (EditorTextRequest) -> Void
  let onError: (Error) -> Void

  func makeUIViewController(context: Context) -> InkEditorViewController {
    InkEditorViewController(
      document: document,
      onEditCommitted: onEditCommitted,
      onCurrentPageChanged: onCurrentPageChanged,
      onPageCommandHandled: onPageCommandHandled,
      onTextRequested: onTextRequested,
      onError: onError)
  }

  func updateUIViewController(_ uiViewController: InkEditorViewController, context: Context) {
    uiViewController.applyHostState(
      tool: tool,
      eraserMode: eraserMode,
      selectorMode: selectorMode,
      spaceMode: spaceMode,
      pens: pens,
      revision: revision,
      arrangement: arrangement,
      activeLayerID: activeLayerID,
      fitRevision: fitRevision,
      targetPage: targetPage,
      navigationRevision: navigationRevision,
      pageCommand: pageCommand)
  }
}

@MainActor
struct InkEditorView: View {
  let document: EngineDocument
  let arrangement: EditorPageArrangement
  let fitRevision: Int
  @Binding var penLibrary: EditorPenLibrary
  @Binding var tool: EditorTool
  @Binding var activeLayerID: String?
  @Binding var currentPage: Int
  @Binding var documentRevision: Int
  @Binding var pageNavigationRevision: Int
  @Binding var pageCommand: EditorPageCommand?
  @State private var selectorMode: EditorSelectorMode = .freehand
  @State private var eraserMode: EditorEraserMode = .stroke
  @State private var spaceMode: EditorSpaceMode = .reflow
  @State private var textRequest: EditorTextRequest?
  let onEditCommitted: () -> Void
  let onPensChanged: (EditorPenLibrary) -> Void
  let onInsertImage: () -> Void
  let onError: (Error) -> Void

  var body: some View {
    ZStack(alignment: .topLeading) {
      InkEditorHost(
        document: document,
        eraserMode: eraserMode,
        selectorMode: selectorMode,
        spaceMode: spaceMode,
        tool: tool,
        pens: penLibrary.tools,
        arrangement: arrangement,
        activeLayerID: activeLayerID,
        fitRevision: fitRevision,
        revision: documentRevision,
        targetPage: currentPage,
        navigationRevision: pageNavigationRevision,
        pageCommand: pageCommand,
        onEditCommitted: onEditCommitted,
        onCurrentPageChanged: { currentPage = $0 },
        onPageCommandHandled: {
          DispatchQueue.main.async {
            pageCommand = nil
          }
        },
        onTextRequested: { request in
          DispatchQueue.main.async {
            textRequest = request
          }
        },
        onError: onError)

      EditorToolRail(
        tool: $tool,
        eraserMode: $eraserMode,
        selectorMode: $selectorMode,
        spaceMode: $spaceMode,
        penLibrary: $penLibrary,
        undo: { history(redo: false) },
        redo: { history(redo: true) },
        insertText: { pageCommand = .requestTextAtCenter },
        insertImage: onInsertImage,
        onPensChanged: onPensChanged)
    }
    .sheet(item: $textRequest) { request in
      TextEditorSheet(
        request: request,
        onSave: { properties in
          pageCommand = .commitText(request, properties)
          textRequest = nil
        },
        onCancel: { textRequest = nil })
    }
  }

  private func history(redo: Bool) {
    do {
      let step: EngineHistoryStep?
      if redo {
        step = try document.redo()
      } else {
        step = try document.undo()
      }
      guard let step else { return }
      let count = try document.pageCount()
      currentPage = min(max(step.page, 0), max(0, count - 1))
      let layers = try document.layers()
      if let activeLayerID,
        !layers.contains(where: { $0.id == activeLayerID })
      {
        self.activeLayerID =
          layers.first(where: { !$0.hidden && !$0.locked })?.id ?? layers.first?.id
      }
      documentRevision &+= 1
      pageNavigationRevision &+= 1
      onEditCommitted()
    } catch {
      onError(error)
    }
  }
}
