import MJRefresh
import QuartzCore
import SwiftUI
import UIKit

enum EditorPageCommand: Equatable {
  case select(Int)
  case clear(Int)
  case addBookmark
  case linkSelection(String)
  case jumpToMark(EngineNavigationMark)
  case requestTextAtCenter
  case commitText(EditorTextRequest, EngineTextProperties)
  case pasteSVGAtCenter(String, placeAtPointer: Bool)
  case pasteSVG(String, at: CGPoint, placeAtPointer: Bool)
  case toggleFigureCapture(Int)
}

@MainActor
final class InkEditorViewController: UIViewController, UIScrollViewDelegate, UIContextMenuInteractionDelegate, UIDragInteractionDelegate {
  private let document: EngineDocument
  private let scrollView = UIScrollView()
  private let documentView = UIView()
  private let onFocusRequested: () -> Void
  private let onViewportChanged: (EditorLinkedViewport) -> Void
  private let onEditCommitted: () -> Void
  private let onCurrentPageChanged: (Int) -> Void
  private let onPageCommandHandled: () -> Void
  private let onBookmarkModeChanged: (Bool) -> Void
  private let onTextRequested: (EditorTextRequest) -> Void
  private let onLinkSelectionRequested: (Int) -> Void
  private let onFollowLink: (String, Int) -> Void
  private let onSaveClipping: (String) -> Void
  private let onFigureCaptureChanged: (Bool) -> Void
  private let onFigureSourceChanged: (String) -> Void
  private let onEditFigure: (String) -> Void
  private let onError: (Error) -> Void
  private lazy var canvasView = InkCanvasView(
    document: document,
    onInteractionBegan: { [weak self] in self?.onFocusRequested() },
    onInteractionEnded: { [weak self] in self?.canvasInteractionEnded() })
  private let selectionBar = UIStackView()
  private var editFigureButton: UIButton?
  private let figureGenerator = FigureTikZGenerator()
  private var figureCaptureActive = false
  private var figureCompleting = false
  private var figurePreviewGeneration = 0
  private var reportedFigureID: String?
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
  private var bookmarkMode = false
  private var hostActive = true
  private var hostFocused = true
  private var hostLinked = false
  private var applyingLinkedViewport = false
  private var lastAppliedLinkedViewport: EditorLinkedViewport?
  private var requestedLinkedViewport: EditorLinkedViewport?
  private var lastLayoutSize = CGSize.zero
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
    onFocusRequested: @escaping () -> Void = {},
    onViewportChanged: @escaping (EditorLinkedViewport) -> Void = { _ in },
    onEditCommitted: @escaping () -> Void = {},
    onCurrentPageChanged: @escaping (Int) -> Void = { _ in },
    onPageCommandHandled: @escaping () -> Void = {},
    onBookmarkModeChanged: @escaping (Bool) -> Void = { _ in },
    onTextRequested: @escaping (EditorTextRequest) -> Void = { _ in },
    onLinkSelectionRequested: @escaping (Int) -> Void = { _ in },
    onFollowLink: @escaping (String, Int) -> Void = { _, _ in },
    onSaveClipping: @escaping (String) -> Void = { _ in },
    onFigureCaptureChanged: @escaping (Bool) -> Void = { _ in },
    onFigureSourceChanged: @escaping (String) -> Void = { _ in },
    onEditFigure: @escaping (String) -> Void = { _ in },
    onError: @escaping (Error) -> Void = { _ in }
  ) {
    self.document = document
    self.onFocusRequested = onFocusRequested
    self.onViewportChanged = onViewportChanged
    self.onEditCommitted = onEditCommitted
    self.onCurrentPageChanged = onCurrentPageChanged
    self.onPageCommandHandled = onPageCommandHandled
    self.onBookmarkModeChanged = onBookmarkModeChanged
    self.onTextRequested = onTextRequested
    self.onLinkSelectionRequested = onLinkSelectionRequested
    self.onFollowLink = onFollowLink
    self.onSaveClipping = onSaveClipping
    self.onFigureCaptureChanged = onFigureCaptureChanged
    self.onFigureSourceChanged = onFigureSourceChanged
    self.onEditFigure = onEditFigure
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
    canvasView.addInteraction(UIDragInteraction(delegate: self))
    let directTap = UITapGestureRecognizer(target: self, action: #selector(handleDirectTap))
    directTap.cancelsTouchesInView = false
    directTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
    canvasView.addGestureRecognizer(directTap)

    let pencilTap = UITapGestureRecognizer(target: self, action: #selector(handlePencilModeTap))
    pencilTap.cancelsTouchesInView = false
    pencilTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
    canvasView.addGestureRecognizer(pencilTap)
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let layoutSizeChanged = scrollView.bounds.size != lastLayoutSize
    lastLayoutSize = scrollView.bounds.size

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
    if layoutSizeChanged, hostLinked {
      if hostFocused {
        DispatchQueue.main.async { [weak self] in
          self?.publishLinkedViewport()
        }
      } else if let requestedLinkedViewport,
        applyLinkedViewport(requestedLinkedViewport)
      {
        lastAppliedLinkedViewport = requestedLinkedViewport
      }
    }
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
    bookmarkMode: Bool,
    targetPage: Int,
    navigationRevision: Int,
    pageCommand: EditorPageCommand?,
    active: Bool,
    focused: Bool,
    linked: Bool,
    linkedViewport: EditorLinkedViewport?
  ) {
    loadViewIfNeeded()

    if active != hostActive {
      hostActive = active
      view.isUserInteractionEnabled = active
      canvasView.setActive(active)
      if !active {
        view.endEditing(true)
      }
    }

    let linkedBecameEnabled = linked && !hostLinked
    hostFocused = focused
    hostLinked = linked
    requestedLinkedViewport = linked ? linkedViewport : nil
    if !linked {
      lastAppliedLinkedViewport = nil
    }

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

    if bookmarkMode != self.bookmarkMode {
      self.bookmarkMode = bookmarkMode
    }
    syncDrawingSuppression()

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

    if linked, !focused,
      let linkedViewport,
      linkedViewport != lastAppliedLinkedViewport,
      applyLinkedViewport(linkedViewport)
    {
      lastAppliedLinkedViewport = linkedViewport
    }
    if linkedBecameEnabled, focused {
      DispatchQueue.main.async { [weak self] in
        self?.publishLinkedViewport()
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
    publishLinkedViewport()
  }

  func scrollViewDidZoom(_ scrollView: UIScrollView) {
    updateContentInsets()
    syncCanvasTransform()
    refreshSelectionBar()
    publishLinkedViewport()
  }

  func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
    onFocusRequested()
  }

  func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
    onFocusRequested()
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

  func dragInteraction(
    _ interaction: UIDragInteraction,
    itemsForBeginning session: UIDragSession
  ) -> [UIDragItem] {
    onFocusRequested()
    guard !figureCaptureActive, !figureCompleting else { return [] }
    let location = session.location(in: canvasView)
    guard let selection = canvasView.selectionFrame(), selection.contains(location) else { return [] }
    do {
      guard let svg = try canvasView.copySelection(), !svg.isEmpty else { return [] }
      return [UIDragItem(itemProvider: NSItemProvider(object: svg as NSString))]
    } catch {
      onError(error)
      return []
    }
  }

  func contextMenuInteraction(
    _ interaction: UIContextMenuInteraction,
    configurationForMenuAtLocation location: CGPoint
  ) -> UIContextMenuConfiguration? {
    onFocusRequested()
    let svg = UIPasteboard.general.string
    let canPaste = svg?.isEmpty == false
    let canSaveClipping = canvasView.selectionFrame() != nil
    guard canPaste || canSaveClipping else { return nil }

    return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
      var actions: [UIMenuElement] = []
      if let svg, !svg.isEmpty {
        actions.append(UIAction(
          title: "Paste",
          image: UIImage(systemName: "doc.on.clipboard")
        ) { [weak self] _ in
          self?.paste(svg, at: location)
        })
      }
      if canSaveClipping {
        actions.append(UIAction(
          title: "Save to Clippings",
          image: UIImage(systemName: "tray.and.arrow.down")
        ) { [weak self] _ in
          self?.saveClipping()
        })
      }
      return UIMenu(children: actions)
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
    let editFigure = selectionButton(
      label: "Edit figure", systemImage: "scribble.variable", action: #selector(editSelectedFigure))
    editFigureButton = editFigure
    selectionBar.addArrangedSubview(editFigure)
    selectionBar.addArrangedSubview(selectionButton(
      label: "Bookmark selection", systemImage: "bookmark", action: #selector(bookmarkSelection)))
    selectionBar.addArrangedSubview(selectionButton(
      label: "Link selection", systemImage: "link", action: #selector(linkSelection)))
    selectionBar.addArrangedSubview(selectionButton(
      label: "Remove bookmark or link", systemImage: "link.badge.minus", action: #selector(ungroupSelection)))
    selectionBar.addArrangedSubview(selectionButton(
      label: "Save to clippings", systemImage: "tray.and.arrow.down", action: #selector(saveClipping)))
    selectionBar.addArrangedSubview(selectionButton(
      label: "Delete selection", systemImage: "trash", action: #selector(deleteSelection)))
    view.addSubview(selectionBar)
  }

  private func selectionButton(label: String, systemImage: String, action: Selector) -> UIButton {
    let button = UIButton(type: .system)
    button.setImage(UIImage(systemName: systemImage), for: .normal)
    button.accessibilityLabel = label
    button.addTarget(self, action: #selector(focusEditor), for: .touchDown)
    button.addTarget(self, action: action, for: .touchUpInside)
    button.widthAnchor.constraint(equalToConstant: 44).isActive = true
    button.heightAnchor.constraint(equalToConstant: 44).isActive = true
    return button
  }

  @objc private func focusEditor() {
    onFocusRequested()
  }

  private func canvasInteractionEnded() {
    if figureCaptureActive {
      refreshFigurePreview()
      refreshSelectionBar()
      return
    }
    onEditCommitted()
    refreshSelectionBar()
  }

  private func refreshSelectionBar() {
    guard isViewLoaded, let selection = canvasView.selectionFrame() else {
      selectionBar.isHidden = true
      return
    }

    selectionBar.isHidden = false
    let selectedFigure = try? canvasView.selectedFigure()
    editFigureButton?.isHidden = selectedFigure == nil
    if selectedFigure != reportedFigureID {
      reportedFigureID = selectedFigure
      if let selectedFigure {
        do {
          onFigureSourceChanged(try document.figureSource(id: selectedFigure))
        } catch {
          onError(error)
        }
      }
    }
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

  @objc private func bookmarkSelection() {
    do {
      try canvasView.bookmarkSelection()
      onEditCommitted()
      refreshSelectionBar()
    } catch {
      onError(error)
    }
  }

  @objc private func linkSelection() {
    guard let page = canvasView.selectionPage() else { return }
    onLinkSelectionRequested(page)
  }

  @objc private func ungroupSelection() {
    do {
      try canvasView.ungroupSelection()
      onEditCommitted()
      refreshSelectionBar()
    } catch {
      onError(error)
    }
  }

  @objc private func editSelectedFigure() {
    do {
      guard let id = try canvasView.selectedFigure() else { return }
      onEditFigure(id)
    } catch {
      onError(error)
    }
  }

  @objc private func saveClipping() {
    do {
      guard let svg = try canvasView.copySelection() else { return }
      onSaveClipping(svg)
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
      case .addBookmark:
        if canvasView.selectionFrame() != nil {
          try canvasView.bookmarkSelection()
          onEditCommitted()
        } else {
          bookmarkMode = true
          canvasView.setDrawingSuppressed(true)
          onBookmarkModeChanged(true)
        }
      case let .linkSelection(href):
        try canvasView.linkSelection(href)
        onEditCommitted()
      case let .jumpToMark(mark):
        scrollToMark(mark)
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
      case let .pasteSVGAtCenter(svg, placeAtPointer):
        try canvasView.paste(
          svg,
          at: CGPoint(
            x: canvasView.bounds.midX,
            y: canvasView.bounds.midY),
          placeAtPointer: placeAtPointer)
        onEditCommitted()
      case let .pasteSVG(svg, point, placeAtPointer):
        try canvasView.paste(svg, at: point, placeAtPointer: placeAtPointer)
        onEditCommitted()
      case let .toggleFigureCapture(page):
        toggleFigureCapture(page: page)
      }
      refreshSelectionBar()
    } catch {
      onError(error)
    }
  }

  private func syncDrawingSuppression() {
    canvasView.setDrawingSuppressed(
      bookmarkMode || appliedTool == .text || figureCompleting)
  }

  private func refreshFigurePreview() {
    guard figureCaptureActive, !figureCompleting else { return }
    do {
      let scene = try canvasView.figureScene()
      figurePreviewGeneration &+= 1
      let generation = figurePreviewGeneration
      Task { @MainActor [weak self] in
        guard let self else { return }
        do {
          let generated = try await self.figureGenerator.generate(scene: scene)
          guard self.figureCaptureActive, generation == self.figurePreviewGeneration else { return }
          self.onFigureSourceChanged(generated.source)
        } catch {
          self.onError(error)
        }
      }
    } catch {
      onError(error)
    }
  }

  private func toggleFigureCapture(page: Int) {
    if !figureCaptureActive {
      do {
        try canvasView.beginFigure(page: page)
        figureCaptureActive = true
        figurePreviewGeneration &+= 1
        onFigureSourceChanged("")
        onFigureCaptureChanged(true)
      } catch {
        onError(error)
      }
      return
    }

    guard !figureCompleting else { return }
    do {
      let scene = try canvasView.figureScene()
      figureCompleting = true
      figurePreviewGeneration &+= 1
      syncDrawingSuppression()
      Task { @MainActor [weak self] in
        guard let self else { return }
        do {
          let generated = try await self.figureGenerator.generate(scene: scene)
          let id = try self.canvasView.completeFigure(
            scene: generated.scene,
            tikz: generated.source)
          self.figureCaptureActive = false
          self.figureCompleting = false
          self.syncDrawingSuppression()
          self.onFigureSourceChanged(generated.source)
          self.onFigureCaptureChanged(false)
          if !id.isEmpty {
            self.onEditCommitted()
            self.refreshSelectionBar()
            self.onEditFigure(id)
          }
        } catch {
          self.figureCompleting = false
          self.syncDrawingSuppression()
          self.onError(error)
        }
      }
    } catch {
      onError(error)
    }
  }

  @objc private func handleDirectTap(_ recognizer: UITapGestureRecognizer) {
    guard recognizer.state == .ended else { return }
    onFocusRequested()
    let point = recognizer.location(in: canvasView)
    guard !handleModeTap(at: point), !figureCaptureActive, !figureCompleting else { return }
    followLink(at: point)
  }

  @objc private func handlePencilModeTap(_ recognizer: UITapGestureRecognizer) {
    guard recognizer.state == .ended else { return }
    onFocusRequested()
    _ = handleModeTap(at: recognizer.location(in: canvasView))
  }

  @discardableResult
  private func handleModeTap(at point: CGPoint) -> Bool {
    if bookmarkMode {
      do {
        try canvasView.addBookmark(at: point)
        onEditCommitted()
        refreshSelectionBar()
      } catch {
        onError(error)
      }
      return true
    }
    if appliedTool == .text {
      requestText(at: point)
      return true
    }
    return false
  }

  private func followLink(at point: CGPoint) {
    do {
      guard let page = canvasView.page(at: point) else { return }
      let pageRect = try document.pageRect(index: page)
      let contentPoint = documentView.convert(point, from: canvasView)
      let local = CGPoint(
        x: contentPoint.x - pageRect.minX,
        y: contentPoint.y - pageRect.minY)

      let marks = try document.navigation()
      for mark in marks.reversed() where mark.page == page && !mark.href.isEmpty {
        guard let x = mark.x, let y = mark.y, let width = mark.width, let height = mark.height else {
          continue
        }
        if CGRect(x: x, y: y, width: width, height: height).contains(local) {
          onFollowLink(mark.href, page)
          return
        }
      }
    } catch {
      onError(error)
    }
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

  private func linkedFitScale() -> CGFloat? {
    guard scrollView.bounds.width > 0,
      scrollView.bounds.height > 0,
      documentSize.width > 0,
      documentSize.height > 0
    else { return nil }

    let fit: CGFloat
    if appliedArrangement == .horizontal {
      fit = max(1, scrollView.bounds.height - 32) / documentSize.height
    } else {
      fit = max(1, scrollView.bounds.width - 32) / documentSize.width
    }
    return min(
      max(fit, scrollView.minimumZoomScale),
      scrollView.maximumZoomScale)
  }

  private func currentLinkedViewport() -> EditorLinkedViewport? {
    guard let fit = linkedFitScale(),
      fit > 0,
      scrollView.zoomScale > 0
    else { return nil }

    let center = documentView.convert(
      CGPoint(x: canvasView.bounds.midX, y: canvasView.bounds.midY),
      from: canvasView)
    return EditorLinkedViewport(
      relativeScale: scrollView.zoomScale / fit,
      center: center)
  }

  private func publishLinkedViewport() {
    guard hostActive,
      hostFocused,
      hostLinked,
      !applyingLinkedViewport,
      let viewport = currentLinkedViewport()
    else { return }
    onViewportChanged(viewport)
  }

  private func applyLinkedViewport(_ viewport: EditorLinkedViewport) -> Bool {
    guard let fit = linkedFitScale() else { return false }

    applyingLinkedViewport = true
    defer { applyingLinkedViewport = false }

    let zoom = min(
      max(
        fit * viewport.relativeScale,
        scrollView.minimumZoomScale),
      scrollView.maximumZoomScale)
    scrollView.setZoomScale(zoom, animated: false)
    updateContentInsets()

    let inset = scrollView.adjustedContentInset
    let minimumX = -inset.left
    let minimumY = -inset.top
    let maximumX = max(
      minimumX,
      documentSize.width * zoom - scrollView.bounds.width + inset.right)
    let maximumY = max(
      minimumY,
      documentSize.height * zoom - scrollView.bounds.height + inset.bottom)
    let x = min(
      max(
        viewport.center.x * zoom - scrollView.bounds.width / 2,
        minimumX),
      maximumX)
    let y = min(
      max(
        viewport.center.y * zoom - scrollView.bounds.height / 2,
        minimumY),
      maximumY)
    scrollView.setContentOffset(
      CGPoint(x: x, y: y),
      animated: false)
    syncCanvasTransform()
    refreshSelectionBar()
    return true
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

  private func scrollToMark(_ mark: EngineNavigationMark) {
    do {
      guard let markX = mark.x, let markY = mark.y else {
        throw EngineDocumentError.operation(
          "Open navigation destination", "The destination has no position")
      }
      fitPages(animated: false)
      view.layoutIfNeeded()
      let page = try document.pageRect(index: mark.page)
      let zoom = scrollView.zoomScale
      let inset = scrollView.adjustedContentInset
      let minimumX = -inset.left
      let minimumY = -inset.top
      let maximumX = max(
        minimumX,
        documentSize.width * zoom - scrollView.bounds.width + inset.right)
      let maximumY = max(
        minimumY,
        documentSize.height * zoom - scrollView.bounds.height + inset.bottom)
      let target = CGPoint(
        x: (page.minX + markX) * zoom,
        y: (page.minY + markY) * zoom)
      let x: CGFloat
      let y: CGFloat
      if appliedArrangement == .horizontal {
        x = min(max(target.x - 48, minimumX), maximumX)
        y = min(max(scrollView.contentOffset.y, minimumY), maximumY)
      } else {
        x = min(max(scrollView.contentOffset.x, minimumX), maximumX)
        y = min(max(target.y - 48, minimumY), maximumY)
      }
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
  let bookmarkMode: Bool
  let revision: Int
  let targetPage: Int
  let navigationRevision: Int
  let pageCommand: EditorPageCommand?
  let active: Bool
  let focused: Bool
  let linked: Bool
  let linkedViewport: EditorLinkedViewport?
  let onFocus: () -> Void
  let onViewportChanged: (EditorLinkedViewport) -> Void
  let onEditCommitted: () -> Void
  let onCurrentPageChanged: (Int) -> Void
  let onPageCommandHandled: () -> Void
  let onBookmarkModeChanged: (Bool) -> Void
  let onTextRequested: (EditorTextRequest) -> Void
  let onLinkSelectionRequested: (Int) -> Void
  let onFollowLink: (String, Int) -> Void
  let onSaveClipping: (String) -> Void
  let onFigureCaptureChanged: (Bool) -> Void
  let onFigureSourceChanged: (String) -> Void
  let onEditFigure: (String) -> Void
  let onError: (Error) -> Void

  func makeUIViewController(context: Context) -> InkEditorViewController {
    InkEditorViewController(
      document: document,
      onFocusRequested: onFocus,
      onViewportChanged: onViewportChanged,
      onEditCommitted: onEditCommitted,
      onCurrentPageChanged: onCurrentPageChanged,
      onPageCommandHandled: onPageCommandHandled,
      onBookmarkModeChanged: onBookmarkModeChanged,
      onTextRequested: onTextRequested,
      onLinkSelectionRequested: onLinkSelectionRequested,
      onFollowLink: onFollowLink,
      onSaveClipping: onSaveClipping,
      onFigureCaptureChanged: onFigureCaptureChanged,
      onFigureSourceChanged: onFigureSourceChanged,
      onEditFigure: onEditFigure,
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
      bookmarkMode: bookmarkMode,
      targetPage: targetPage,
      navigationRevision: navigationRevision,
      pageCommand: pageCommand,
      active: active,
      focused: focused,
      linked: linked,
      linkedViewport: linkedViewport)
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
  @Binding var bookmarkMode: Bool
  @Binding var currentPage: Int
  @Binding var documentRevision: Int
  @Binding var pageNavigationRevision: Int
  @Binding var pageCommand: EditorPageCommand?
  let active: Bool
  let focused: Bool
  let linked: Bool
  let linkedViewport: EditorLinkedViewport?
  @State private var selectorMode: EditorSelectorMode = .freehand
  @State private var eraserMode: EditorEraserMode = .stroke
  @State private var spaceMode: EditorSpaceMode = .reflow
  @State private var textRequest: EditorTextRequest?
  @State private var drawing = false
  @State private var figureSource = ""
  let onFocus: () -> Void
  let onViewportChanged: (EditorLinkedViewport) -> Void
  let onEditCommitted: () -> Void
  let onPensChanged: (EditorPenLibrary) -> Void
  let onInsertImage: () -> Void
  let onShowClippings: () -> Void
  let onSaveClipping: (String) -> Void
  let onLinkSelectionRequested: (Int) -> Void
  let onFollowLink: (String, Int) -> Void
  let onDropClipping: (String, CGPoint) -> Bool
  let onDropSelection: (String, CGPoint) -> Bool
  let onCaptureChanged: (Bool) -> Void
  let onEditFigure: (String) -> Void
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
        bookmarkMode: bookmarkMode,
        revision: documentRevision,
        targetPage: currentPage,
        navigationRevision: pageNavigationRevision,
        pageCommand: pageCommand,
        active: active,
        focused: focused,
        linked: linked,
        linkedViewport: linkedViewport,
        onFocus: onFocus,
        onViewportChanged: onViewportChanged,
        onEditCommitted: {
          documentRevision &+= 1
          onEditCommitted()
        },
        onCurrentPageChanged: { currentPage = $0 },
        onPageCommandHandled: {
          DispatchQueue.main.async {
            pageCommand = nil
          }
        },
        onBookmarkModeChanged: { active in
          DispatchQueue.main.async {
            bookmarkMode = active
          }
        },
        onTextRequested: { request in
          DispatchQueue.main.async {
            textRequest = request
          }
        },
        onLinkSelectionRequested: onLinkSelectionRequested,
        onFollowLink: onFollowLink,
        onSaveClipping: onSaveClipping,
        onFigureCaptureChanged: { capture in
          drawing = capture
          onCaptureChanged(capture)
        },
        onFigureSourceChanged: { figureSource = $0 },
        onEditFigure: onEditFigure,
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
        drawing: drawing,
        toggleDrawing: {
          if !drawing, ![EditorTool.pen, .marker, .highlighter].contains(tool) {
            tool = .pen
          }
          pageCommand = .toggleFigureCapture(currentPage)
        },
        showClippings: onShowClippings,
        onPensChanged: onPensChanged)

      if drawing || !figureSource.isEmpty {
        VStack(alignment: .leading, spacing: 10) {
          HStack {
            Text("TikZ figure")
              .font(.headline)
            Spacer()
            Button("Copy", systemImage: "doc.on.doc") {
              UIPasteboard.general.string = figureSource
            }
            .labelStyle(.iconOnly)
            .disabled(figureSource.isEmpty)
          }
          ScrollView {
            Text(figureSource.isEmpty ? "Draw on the page to build the figure." : figureSource)
              .font(.system(.caption, design: .monospaced))
              .foregroundStyle(figureSource.isEmpty ? .secondary : .primary)
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .topLeading)
          }
          if !drawing {
            Button("Close figure preview") {
              figureSource = ""
            }
          }
        }
        .padding(16)
        .frame(minWidth: 280, maxWidth: 280, minHeight: 260, maxHeight: 520, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
          RoundedRectangle(cornerRadius: 16)
            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(8)
      }

      if bookmarkMode {
        HStack(spacing: 10) {
          Image(systemName: "bookmark")
          Text("Add Bookmark")
            .fontWeight(.semibold)
          Text("Tap the line to mark.")
            .foregroundStyle(.secondary)
          Button("Done") {
            bookmarkMode = false
          }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.top, 8)
        .padding(.horizontal, 80)
      }
    }
    .dropDestination(for: String.self) { values, location in
      onFocus()
      guard !drawing, let value = values.first else { return false }
      return onDropClipping(value, location)
        || onDropSelection(value, location)
    }
    .simultaneousGesture(
      TapGesture().onEnded { onFocus() })
    .onChange(of: documentRevision) {
      normalizeViewState()
    }
    .onChange(of: tool) {
      if bookmarkMode { bookmarkMode = false }
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


  private func normalizeViewState() {
    do {
      let count = try document.pageCount()
      let nextPage = min(max(currentPage, 0), max(0, count - 1))
      if nextPage != currentPage {
        currentPage = nextPage
        pageNavigationRevision &+= 1
      }
      let layers = try document.layers()
      if let activeLayerID,
        !layers.contains(where: { $0.id == activeLayerID })
      {
        self.activeLayerID =
          layers.first(where: { !$0.hidden && !$0.locked })?.id
            ?? layers.first?.id
      }
    } catch {
      onError(error)
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
      pageNavigationRevision &+= 1
      onEditCommitted()
    } catch {
      onError(error)
    }
  }
}
