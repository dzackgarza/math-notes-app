import MJRefresh
import QuartzCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

private let notebookSelectionDragType = UTType(
  exportedAs: "dev.zack.mathnotes.selection-drag")

@MainActor
private struct NotebookEditorDropDelegate: DropDelegate {
  let canDrop: () -> Bool
  let onFocus: () -> Void
  let onDropClipping: (String, CGPoint) -> Bool
  let onDropSelection: (String, CGPoint) -> Bool

  func dropUpdated(info: DropInfo) -> DropProposal? {
    DropProposal(
      operation: info.hasItemsConforming(to: [notebookSelectionDragType])
        ? .move
        : .copy)
  }

  func validateDrop(info: DropInfo) -> Bool {
    canDrop()
  }

  func performDrop(info: DropInfo) -> Bool {
    guard canDrop() else { return false }
    onFocus()
    let location = info.location

    if let provider = info.itemProviders(for: [notebookSelectionDragType]).first {
      provider.loadDataRepresentation(
        forTypeIdentifier: notebookSelectionDragType.identifier
      ) { data, _ in
        guard let data, let svg = String(data: data, encoding: .utf8) else { return }
        Task { @MainActor in
          _ = onDropSelection(svg, location)
        }
      }
      return true
    }

    guard let provider = info.itemProviders(for: [.plainText]).first else {
      return false
    }
    provider.loadObject(ofClass: NSString.self) { object, _ in
      guard let string = object as? NSString else { return }
      Task { @MainActor in
        let value = string as String
        _ = onDropClipping(value, location) || onDropSelection(value, location)
      }
    }
    return true
  }
}

enum EditorPageCommand: Equatable {
  case select(Int)
  case clear(Int)
  case addBookmark
  case linkSelection(String)
  case saveSelectionToClippings
  case recolorSelection(UInt32)
  case jumpToMark(EngineNavigationMark)
  case requestTextAtCenter
  case commitText(EditorTextRequest, EngineTextProperties)
  case pasteSVGAtCenter(String, placeAtPointer: Bool)
  case pasteSVG(String, at: CGPoint, placeAtPointer: Bool)
  case toggleFigureCapture(Int)
}

@MainActor
final class InkEditorViewController: UIViewController, UIScrollViewDelegate, UIEditMenuInteractionDelegate, UIDragInteractionDelegate, UIPencilInteractionDelegate {
  private static let deskMargin: CGFloat = 16
  private static let toolRailInset: CGFloat = 8
  private static let toolRailWidth: CGFloat = 60
  private static let deskLeadingMargin = toolRailInset + toolRailWidth + deskMargin

  private let document: EngineDocument
  private let scrollView = UIScrollView()
  private let documentView = UIView()
  private let onFocusRequested: () -> Void
  private let onViewportChanged: (EditorLinkedViewport) -> Void
  private let onEditCommitted: () -> Void
  private let onSaveRequested: () -> Void
  private let onCurrentPageChanged: (Int) -> Void
  private let onPageCommandHandled: () -> Void
  private let onBookmarkModeChanged: (Bool) -> Void
  private let onTextRequested: (EditorTextRequest) -> Void
  private let onLinkSelectionRequested: (Int) -> Void
  private let onFollowLink: (String, Int) -> Void
  private let onSaveClipping: (String) -> Void
  private let onSelectionChanged: (Bool) -> Void
  private let onUndo: () -> Void
  private let onRedo: () -> Void
  private let onPencilAction: (UIPencilPreferredAction) -> Void
  private let onFigureCaptureChanged: (Bool) -> Void
  private let onFigureSourceChanged: (String) -> Void
  private let onEditFigure: (String) -> Void
  private let onError: (Error) -> Void
  private lazy var canvasView = InkCanvasView(
    document: document,
    onInteractionBegan: { [weak self] in
      self?.onFocusRequested()
      self?.becomeFirstResponder()
    },
    onInteractionEnded: { [weak self] in self?.canvasInteractionEnded() })
  private let selectionBar = UIStackView()
  private var editFigureButton: UIButton?
  private var selectionColorButton: UIButton?
  private var saveClippingButton: UIButton?
  private var clippingsPanelOpen = false
  private let figureGenerator = FigureTikZGenerator()
  private var figureCaptureActive = false
  private var figureCompleting = false
  private var figurePreviewGeneration = 0
  private var reportedFigureID: String?
  private var reportedSelectionActive = false
  private var documentSize: CGSize
  private var setInitialZoom = false
  private var appliedTool: EditorTool = .pen
  private var appliedEraserMode: EditorEraserMode = .stroke
  private var appliedSelectorMode: EditorSelectorMode = .freehand
  private var appliedSpaceMode: EditorSpaceMode = .reflow
  private var appliedPens = EditorPenSet.defaults
  private var appliedPalette: [UInt32] = []
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
  private var fingerDrawing = false
  private var pageEditMenuInteraction: UIEditMenuInteraction?
  private var pageLongPress: UILongPressGestureRecognizer?
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
    onSaveRequested: @escaping () -> Void = {},
    onCurrentPageChanged: @escaping (Int) -> Void = { _ in },
    onPageCommandHandled: @escaping () -> Void = {},
    onBookmarkModeChanged: @escaping (Bool) -> Void = { _ in },
    onTextRequested: @escaping (EditorTextRequest) -> Void = { _ in },
    onLinkSelectionRequested: @escaping (Int) -> Void = { _ in },
    onFollowLink: @escaping (String, Int) -> Void = { _, _ in },
    onSaveClipping: @escaping (String) -> Void = { _ in },
    onSelectionChanged: @escaping (Bool) -> Void = { _ in },
    onUndo: @escaping () -> Void = {},
    onRedo: @escaping () -> Void = {},
    onPencilAction: @escaping (UIPencilPreferredAction) -> Void = { _ in },
    onFigureCaptureChanged: @escaping (Bool) -> Void = { _ in },
    onFigureSourceChanged: @escaping (String) -> Void = { _ in },
    onEditFigure: @escaping (String) -> Void = { _ in },
    onError: @escaping (Error) -> Void = { _ in }
  ) {
    self.document = document
    self.onFocusRequested = onFocusRequested
    self.onViewportChanged = onViewportChanged
    self.onEditCommitted = onEditCommitted
    self.onSaveRequested = onSaveRequested
    self.onCurrentPageChanged = onCurrentPageChanged
    self.onPageCommandHandled = onPageCommandHandled
    self.onBookmarkModeChanged = onBookmarkModeChanged
    self.onTextRequested = onTextRequested
    self.onLinkSelectionRequested = onLinkSelectionRequested
    self.onFollowLink = onFollowLink
    self.onSaveClipping = onSaveClipping
    self.onSelectionChanged = onSelectionChanged
    self.onUndo = onUndo
    self.onRedo = onRedo
    self.onPencilAction = onPencilAction
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

  override var canBecomeFirstResponder: Bool { true }

  override var keyCommands: [UIKeyCommand]? {
    [
      editorKeyCommand("s", modifiers: .command, action: #selector(keyboardSave), title: "Save"),
      editorKeyCommand("z", modifiers: .command, action: #selector(keyboardUndo), title: "Undo"),
      editorKeyCommand(
        "z",
        modifiers: .command.union(.shift),
        action: #selector(keyboardRedo),
        title: "Redo"),
      editorKeyCommand("y", modifiers: .command, action: #selector(keyboardRedo), title: "Redo"),
      editorKeyCommand("a", modifiers: .command, action: #selector(keyboardSelectAll), title: "Select All"),
      editorKeyCommand("c", modifiers: .command, action: #selector(copySelection), title: "Copy"),
      editorKeyCommand("x", modifiers: .command, action: #selector(cutSelection), title: "Cut"),
      editorKeyCommand("v", modifiers: .command, action: #selector(keyboardPaste), title: "Paste"),
      editorKeyCommand("d", modifiers: .command, action: #selector(duplicateSelection), title: "Duplicate"),
      editorKeyCommand(
        UIKeyCommand.inputDelete,
        modifiers: [],
        action: #selector(keyboardDelete),
        title: "Delete Selection"),
      editorKeyCommand(
        UIKeyCommand.inputEscape,
        modifiers: [],
        action: #selector(clearSelection),
        title: "Clear Selection"),
    ]
  }

  deinit {
    pullReadyTimer?.invalidate()
  }

  private func editorKeyCommand(
    _ input: String,
    modifiers: UIKeyModifierFlags,
    action: Selector,
    title: String
  ) -> UIKeyCommand {
    let command = UIKeyCommand(input: input, modifierFlags: modifiers, action: action)
    command.discoverabilityTitle = title
    return command
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    if hostActive, hostFocused { becomeFirstResponder() }
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    view.backgroundColor = NativeTheme.boardUI
    view.addInteraction(UIPencilInteraction(delegate: self))

    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.backgroundColor = NativeTheme.boardUI
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
    let editMenuInteraction = UIEditMenuInteraction(delegate: self)
    pageEditMenuInteraction = editMenuInteraction
    canvasView.addInteraction(editMenuInteraction)
    let pageLongPress = UILongPressGestureRecognizer(target: self, action: #selector(handlePageLongPress))
    pageLongPress.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
    self.pageLongPress = pageLongPress
    canvasView.addGestureRecognizer(pageLongPress)
    canvasView.addInteraction(UIDragInteraction(delegate: self))
    let directTap = UITapGestureRecognizer(target: self, action: #selector(handleDirectTap))
    directTap.cancelsTouchesInView = false
    directTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
    canvasView.addGestureRecognizer(directTap)

    let pencilTap = UITapGestureRecognizer(target: self, action: #selector(handlePencilModeTap))
    pencilTap.cancelsTouchesInView = false
    pencilTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
    canvasView.addGestureRecognizer(pencilTap)

    let undoTap = UITapGestureRecognizer(target: self, action: #selector(handleUndoTap))
    undoTap.cancelsTouchesInView = false
    undoTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
    undoTap.numberOfTouchesRequired = 2
    canvasView.addGestureRecognizer(undoTap)

    let redoTap = UITapGestureRecognizer(target: self, action: #selector(handleRedoTap))
    redoTap.cancelsTouchesInView = false
    redoTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
    redoTap.numberOfTouchesRequired = 3
    canvasView.addGestureRecognizer(redoTap)
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
    palette: [UInt32],
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
    linkedViewport: EditorLinkedViewport?,
    fingerDraws: Bool,
    clippingsOpen: Bool
  ) {
    loadViewIfNeeded()

    let becameActive = active && !hostActive
    if active != hostActive {
      hostActive = active
      view.isUserInteractionEnabled = active
      canvasView.setActive(active)
      if !active {
        view.endEditing(true)
      }
    }

    let linkedBecameEnabled = linked && !hostLinked
    let focusChanged = focused != hostFocused
    hostFocused = focused
    if active && focused && (becameActive || focusChanged) {
      becomeFirstResponder()
    } else if (!active || !focused) && isFirstResponder {
      resignFirstResponder()
    }
    hostLinked = linked
    requestedLinkedViewport = linked ? linkedViewport : nil
    if !linked {
      lastAppliedLinkedViewport = nil
    }

    if fingerDraws != fingerDrawing {
      setFingerDrawing(fingerDraws)
    }

    clippingsPanelOpen = clippingsOpen
    updateSaveClippingVisibility()

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

    if palette != appliedPalette {
      appliedPalette = palette
      updateSelectionColorMenu()
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
      fitPages(animated: true, preserveLeadingPosition: true)
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

  func setFingerDrawing(_ enabled: Bool) {
    fingerDrawing = enabled
    pageLongPress?.isEnabled = !enabled
    if enabled {
      pageEditMenuInteraction?.dismissMenu()
    }
    scrollView.panGestureRecognizer.minimumNumberOfTouches = enabled ? 2 : 1
    canvasView.setFingerDrawing(enabled)
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
    guard !fingerDrawing else { return [] }
    guard !figureCaptureActive, !figureCompleting else { return [] }
    let location = session.location(in: canvasView)
    guard let selection = canvasView.selectionFrame(), selection.contains(location) else { return [] }
    do {
      guard let svg = try canvasView.copySelection(), !svg.isEmpty else { return [] }
      let provider = NSItemProvider(object: svg as NSString)
      provider.registerDataRepresentation(
        forTypeIdentifier: notebookSelectionDragType.identifier,
        visibility: .ownProcess
      ) { completion in
        completion(Data(svg.utf8), nil)
        return nil
      }
      return [UIDragItem(itemProvider: provider)]
    } catch {
      onError(error)
      return []
    }
  }

  func dragInteraction(
    _ interaction: UIDragInteraction,
    session: UIDragSession,
    willEndWith operation: UIDropOperation
  ) {
    guard operation == .move else { return }
    do {
      try canvasView.deleteSelection()
      onEditCommitted()
      refreshSelectionBar()
    } catch {
      onError(error)
    }
  }

  @objc private func handlePageLongPress(_ recognizer: UILongPressGestureRecognizer) {
    guard recognizer.state == .began, !fingerDrawing,
      let pageEditMenuInteraction
    else { return }
    onFocusRequested()
    pageEditMenuInteraction.presentEditMenu(
      with: UIEditMenuConfiguration(
        identifier: nil,
        sourcePoint: recognizer.location(in: canvasView)))
  }

  func editMenuInteraction(
    _ interaction: UIEditMenuInteraction,
    menuFor configuration: UIEditMenuConfiguration,
    suggestedActions: [UIMenuElement]
  ) -> UIMenu? {
    onFocusRequested()
    let location = configuration.sourcePoint
    let svg = UIPasteboard.general.string
    let canSaveClipping = canvasView.selectionFrame() != nil
    var actions: [UIMenuElement] = []
    if !figureCaptureActive, !figureCompleting, let svg, !svg.isEmpty {
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
  private func configureSelectionBar() {
    selectionBar.axis = .horizontal
    selectionBar.spacing = 2
    selectionBar.isLayoutMarginsRelativeArrangement = true
    selectionBar.directionalLayoutMargins = NSDirectionalEdgeInsets(
      top: 2, leading: 2, bottom: 2, trailing: 2)
    selectionBar.backgroundColor = NativeTheme.leafUI
    selectionBar.tintColor = NativeTheme.inkUI
    selectionBar.layer.cornerRadius = 12
    selectionBar.layer.borderColor = NativeTheme.inkUI.withAlphaComponent(0.16).cgColor
    selectionBar.layer.borderWidth = 1
    selectionBar.layer.shadowColor = NativeTheme.inkUI.cgColor
    selectionBar.layer.shadowOpacity = 0.18
    selectionBar.layer.shadowRadius = 8
    selectionBar.layer.shadowOffset = CGSize(width: 0, height: 3)
    selectionBar.isHidden = true

    selectionBar.addArrangedSubview(selectionButton(
      label: "Copy", systemImage: "doc.on.doc", action: #selector(copySelection)))
    selectionBar.addArrangedSubview(selectionButton(
      label: "Cut", systemImage: "scissors", action: #selector(cutSelection)))
    selectionBar.addArrangedSubview(selectionButton(
      label: "Duplicate", systemImage: "plus.square.on.square", action: #selector(duplicateSelection)))
    let selectionColor = selectionMenuButton(
      label: "Recolor selection", systemImage: "paintpalette")
    selectionColorButton = selectionColor
    selectionBar.addArrangedSubview(selectionColor)
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
    let saveClipping = selectionButton(
      label: "Save to clippings", systemImage: "tray.and.arrow.down", action: #selector(saveClipping))
    saveClipping.isHidden = true
    saveClippingButton = saveClipping
    selectionBar.addArrangedSubview(saveClipping)
    let deleteSelection = selectionButton(
      label: "Delete selection", systemImage: "trash", action: #selector(deleteSelection))
    deleteSelection.tintColor = NativeTheme.ribbonUI
    selectionBar.addArrangedSubview(deleteSelection)
    selectionBar.addArrangedSubview(selectionButton(
      label: "Clear selection", systemImage: "xmark", action: #selector(clearSelection)))
    view.addSubview(selectionBar)
  }

  private func selectionButton(label: String, systemImage: String, action: Selector) -> UIButton {
    let button = selectionMenuButton(label: label, systemImage: systemImage)
    button.addTarget(self, action: action, for: .touchUpInside)
    return button
  }

  private func selectionMenuButton(label: String, systemImage: String) -> UIButton {
    let button = UIButton(type: .system)
    button.setImage(UIImage(systemName: systemImage), for: .normal)
    button.tintColor = NativeTheme.inkUI
    button.accessibilityLabel = label
    button.addTarget(self, action: #selector(focusEditor), for: .touchDown)
    button.widthAnchor.constraint(equalToConstant: 44).isActive = true
    button.heightAnchor.constraint(equalToConstant: 44).isActive = true
    return button
  }

  private func updateSelectionColorMenu() {
    guard let button = selectionColorButton else { return }
    button.isEnabled = !appliedPalette.isEmpty
    button.showsMenuAsPrimaryAction = true
    button.menu = UIMenu(
      title: "Selection color",
      children: appliedPalette.map { rgb in
        UIAction(
          title: String(format: "#%06X", rgb & 0xFFFFFF),
          image: selectionColorImage(rgb)
        ) { [weak self] _ in
          self?.recolorSelection(rgb)
        }
      })
  }

  private func selectionColorImage(_ rgb: UInt32) -> UIImage {
    let size = CGSize(width: 18, height: 18)
    return UIGraphicsImageRenderer(size: size).image { context in
      let color = UIColor(
        red: CGFloat((rgb >> 16) & 0xFF) / 255,
        green: CGFloat((rgb >> 8) & 0xFF) / 255,
        blue: CGFloat(rgb & 0xFF) / 255,
        alpha: 1)
      color.setFill()
      context.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
    }
  }

  @objc private func focusEditor() {
    onFocusRequested()
    becomeFirstResponder()
  }

  @objc private func keyboardSave() {
    guard hostActive, hostFocused else { return }
    guard !figureCaptureActive else {
      onError(
        EngineDocumentError.operation(
          "Save notebook",
          "Complete the drawing before saving."))
      return
    }
    onSaveRequested()
  }

  @objc private func keyboardUndo() {
    guard hostActive, hostFocused else { return }
    onUndo()
  }

  @objc private func keyboardRedo() {
    guard hostActive, hostFocused else { return }
    onRedo()
  }

  @objc private func keyboardSelectAll() {
    guard hostActive, hostFocused else { return }
    let center = CGPoint(x: canvasView.bounds.midX, y: canvasView.bounds.midY)
    let page = reportedPage >= 0 ? reportedPage : (canvasView.page(at: center) ?? 0)
    do {
      try canvasView.selectAll(page: page)
      refreshSelectionBar()
    } catch {
      onError(error)
    }
  }

  @objc private func keyboardPaste() {
    guard hostActive, hostFocused,
      let svg = UIPasteboard.general.string,
      svg.contains("<svg")
    else { return }
    paste(svg, at: CGPoint(x: canvasView.bounds.midX, y: canvasView.bounds.midY))
  }

  @objc private func keyboardDelete() {
    guard hostActive, hostFocused, canvasView.selectionFrame() != nil else { return }
    deleteSelection()
  }

  @objc private func clearSelection() {
    guard hostActive, hostFocused, canvasView.selectionFrame() != nil else { return }
    do {
      try canvasView.clearSelection()
      refreshSelectionBar()
    } catch {
      onError(error)
    }
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

  private func updateSaveClippingVisibility() {
    saveClippingButton?.isHidden = !clippingsPanelOpen || figureCaptureActive || figureCompleting
  }

  private func refreshSelectionBar() {
    updateSaveClippingVisibility()
    guard isViewLoaded, let selection = canvasView.selectionFrame() else {
      selectionBar.isHidden = true
      reportSelection(false)
      return
    }

    reportSelection(true)
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

  private func reportSelection(_ active: Bool) {
    guard active != reportedSelectionActive else { return }
    reportedSelectionActive = active
    onSelectionChanged(active)
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
    guard canvasView.selectionFrame() != nil else { return }
    do {
      try canvasView.duplicateSelection()
      onEditCommitted()
      refreshSelectionBar()
    } catch {
      onError(error)
    }
  }

  private func recolorSelection(_ rgb: UInt32) {
    do {
      try canvasView.recolorSelection(rgb)
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
      case .saveSelectionToClippings:
        if let svg = try canvasView.copySelection() {
          onSaveClipping(svg)
        }
      case let .recolorSelection(rgb):
        try canvasView.recolorSelection(rgb)
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
      bookmarkMode || appliedTool == .text || appliedTool == .navigate || figureCompleting)
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
        updateSaveClippingVisibility()
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
      updateSaveClippingVisibility()
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
          self.updateSaveClippingVisibility()
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
          self.updateSaveClippingVisibility()
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
    guard appliedTool == .navigate else { return }
    followLink(at: point)
  }

  @objc private func handlePencilModeTap(_ recognizer: UITapGestureRecognizer) {
    guard recognizer.state == .ended else { return }
    onFocusRequested()
    let point = recognizer.location(in: canvasView)
    if handleModeTap(at: point) { return }
    guard appliedTool == .navigate, !figureCaptureActive, !figureCompleting else { return }
    followLink(at: point)
  }

  @objc private func handleUndoTap(_ recognizer: UITapGestureRecognizer) {
    guard recognizer.state == .ended else { return }
    onFocusRequested()
    onUndo()
  }

  @objc private func handleRedoTap(_ recognizer: UITapGestureRecognizer) {
    guard recognizer.state == .ended else { return }
    onFocusRequested()
    onRedo()
  }

  func pencilInteraction(
    _ interaction: UIPencilInteraction,
    didReceiveTap tap: UIPencilInteraction.Tap
  ) {
    guard hostActive, hostFocused else { return }
    onFocusRequested()
    onPencilAction(UIPencilInteraction.preferredTapAction)
  }

  func pencilInteraction(
    _ interaction: UIPencilInteraction,
    didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze
  ) {
    guard hostActive, hostFocused, squeeze.phase == .ended else { return }
    onFocusRequested()
    onPencilAction(UIPencilInteraction.preferredSqueezeAction)
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

  private func fitPages(
    animated: Bool,
    preserveLeadingPosition: Bool = false
  ) {
    guard let fit = fitScale() else { return }

    let horizontal = appliedArrangement == .horizontal
    let oldInset = scrollView.adjustedContentInset
    let oldZoom = scrollView.zoomScale
    let leadingCoordinate = preserveLeadingPosition
      ? FitScrollPosition.leadingDocumentCoordinate(
        contentOffset: horizontal ? scrollView.contentOffset.x : scrollView.contentOffset.y,
        leadingInset: horizontal ? oldInset.left : oldInset.top,
        zoomScale: oldZoom)
      : nil

    scrollView.setZoomScale(fit, animated: preserveLeadingPosition ? false : animated)
    guard let leadingCoordinate else { return }

    updateContentInsets()
    let inset = scrollView.adjustedContentInset
    let minimumX = -inset.left
    let minimumY = -inset.top
    let maximumX = max(
      minimumX,
      documentSize.width * fit - scrollView.bounds.width + inset.right)
    let maximumY = max(
      minimumY,
      documentSize.height * fit - scrollView.bounds.height + inset.bottom)
    var offset = scrollView.contentOffset
    if horizontal {
      offset.x = FitScrollPosition.contentOffset(
        for: leadingCoordinate,
        leadingInset: inset.left,
        zoomScale: fit,
        minimum: minimumX,
        maximum: maximumX)
      offset.y = minimumY
    } else {
      offset.x = minimumX
      offset.y = FitScrollPosition.contentOffset(
        for: leadingCoordinate,
        leadingInset: inset.top,
        zoomScale: fit,
        minimum: minimumY,
        maximum: maximumY)
    }
    scrollView.setContentOffset(offset, animated: false)
    syncCanvasTransform()
  }

  private func linkedFitScale() -> CGFloat? {
    fitScale()
  }

  private func fitScale() -> CGFloat? {
    guard scrollView.bounds.width > 0,
      scrollView.bounds.height > 0,
      documentSize.width > 0,
      documentSize.height > 0
    else { return nil }

    let availableWidth = max(
      1,
      scrollView.bounds.width - Self.deskLeadingMargin - Self.deskMargin)
    let availableHeight = max(
      1,
      scrollView.bounds.height - 2 * Self.deskMargin)
    let fit = appliedArrangement == .horizontal
      ? availableHeight / documentSize.height
      : availableWidth / documentSize.width
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
    let horizontalExtra = max(
      0,
      scrollView.bounds.width - scaledWidth - Self.deskLeadingMargin - Self.deskMargin)
    let verticalExtra = max(
      0,
      scrollView.bounds.height - scaledHeight - 2 * Self.deskMargin)
    let inset = UIEdgeInsets(
      top: Self.deskMargin + verticalExtra / 2,
      left: Self.deskLeadingMargin + horizontalExtra / 2,
      bottom: Self.deskMargin + verticalExtra / 2,
      right: Self.deskMargin + horizontalExtra / 2)
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
  let palette: [UInt32]
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
  let fingerDraws: Bool
  let clippingsOpen: Bool
  let onFocus: () -> Void
  let onViewportChanged: (EditorLinkedViewport) -> Void
  let onEditCommitted: () -> Void
  let onSaveRequested: () -> Void
  let onCurrentPageChanged: (Int) -> Void
  let onPageCommandHandled: () -> Void
  let onBookmarkModeChanged: (Bool) -> Void
  let onTextRequested: (EditorTextRequest) -> Void
  let onLinkSelectionRequested: (Int) -> Void
  let onFollowLink: (String, Int) -> Void
  let onSaveClipping: (String) -> Void
  let onSelectionChanged: (Bool) -> Void
  let onUndo: () -> Void
  let onRedo: () -> Void
  let onPencilAction: (UIPencilPreferredAction) -> Void
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
      onSaveRequested: onSaveRequested,
      onCurrentPageChanged: onCurrentPageChanged,
      onPageCommandHandled: onPageCommandHandled,
      onBookmarkModeChanged: onBookmarkModeChanged,
      onTextRequested: onTextRequested,
      onLinkSelectionRequested: onLinkSelectionRequested,
      onFollowLink: onFollowLink,
      onSaveClipping: onSaveClipping,
      onSelectionChanged: onSelectionChanged,
      onUndo: onUndo,
      onRedo: onRedo,
      onPencilAction: onPencilAction,
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
      palette: palette,
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
      linkedViewport: linkedViewport,
      fingerDraws: fingerDraws,
      clippingsOpen: clippingsOpen)
  }
}

func editorPageCounterText(currentPage: Int, pageCount: Int) -> String {
  let total = max(1, pageCount)
  let page = min(max(currentPage, 0), total - 1)
  return "\(page + 1) / \(total)"
}

@MainActor
struct InkEditorView: View {
  let document: EngineDocument
  let arrangement: EditorPageArrangement
  let fitRevision: Int
  @Binding var penLibrary: EditorPenLibrary
  @Binding var tool: EditorTool
  @Binding var drawingTool: EditorTool
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
  let fingerDraws: Bool
  let hiddenTools: Set<String>
  @State private var selectorMode: EditorSelectorMode = .freehand
  @State private var eraserMode: EditorEraserMode = .stroke
  @State private var spaceMode: EditorSpaceMode = .reflow
  @State private var textRequest: EditorTextRequest?
  @State private var drawing = false
  @State private var figureSource = ""
  @State private var selectionActive = false
  @State private var previousPencilTool: EditorTool?
  let onFocus: () -> Void
  let onViewportChanged: (EditorLinkedViewport) -> Void
  let onEditCommitted: () -> Void
  let onSaveRequested: () -> Void
  let onPensChanged: (EditorPenLibrary) -> Void
  let onInsertImage: () -> Void
  let clippingsOpen: Bool
  let onShowClippings: () -> Void
  let onSaveClipping: (String) -> Void
  let onSelectionChanged: (Bool) -> Void
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
        palette: penLibrary.palette,
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
        fingerDraws: fingerDraws,
        clippingsOpen: clippingsOpen,
        onFocus: onFocus,
        onViewportChanged: onViewportChanged,
        onEditCommitted: {
          documentRevision &+= 1
          onEditCommitted()
        },
        onSaveRequested: onSaveRequested,
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
        onSelectionChanged: { active in
          DispatchQueue.main.async {
            selectionActive = active
            onSelectionChanged(active)
          }
        },
        onUndo: { _ = history(redo: false) },
        onRedo: { _ = history(redo: true) },
        onPencilAction: applyPencilAction,
        onFigureCaptureChanged: { capture in
          drawing = capture
          onCaptureChanged(capture)
        },
        onFigureSourceChanged: { figureSource = $0 },
        onEditFigure: onEditFigure,
        onError: onError)

      EditorToolRail(
        tool: $tool,
        drawingTool: $drawingTool,
        eraserMode: $eraserMode,
        selectorMode: $selectorMode,
        spaceMode: $spaceMode,
        penLibrary: $penLibrary,
        hiddenTools: hiddenTools,
        undo: { history(redo: false) },
        redo: { history(redo: true) },
        insertText: { pageCommand = .requestTextAtCenter },
        insertImage: onInsertImage,
        drawing: drawing,
        selectionActive: selectionActive,
        clippingsOpen: clippingsOpen,
        toggleDrawing: toggleDrawingMode,
        showClippings: onShowClippings,
        recolorSelection: { rgb in pageCommand = .recolorSelection(rgb) },
        onPensChanged: onPensChanged)

      if drawing || !figureSource.isEmpty {
        VStack(alignment: .leading, spacing: 10) {
          HStack {
            Text("TikZ figure")
              .font(NativeTheme.headline)
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
              .foregroundStyle(figureSource.isEmpty ? NativeTheme.graphite : NativeTheme.ink)
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
        .foregroundStyle(NativeTheme.ink)
        .background(NativeTheme.leaf, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
          RoundedRectangle(cornerRadius: 16)
            .stroke(NativeTheme.separator, lineWidth: 1)
        }
        .shadow(color: NativeTheme.ink.opacity(0.18), radius: 9, y: 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(8)
      }

      if let mode = modeBannerLabel {
        HStack(spacing: 10) {
          Text(mode)
            .font(NativeTheme.subhead)
          if bookmarkMode && !drawing {
            Text("Tap the line to mark.")
              .font(NativeTheme.callout)
              .foregroundStyle(NativeTheme.graphite)
          }
          if drawing {
            Button("Complete") {
              toggleDrawingMode()
            }
          } else {
            Button {
              closeModeBanner()
            } label: {
              Image(systemName: "xmark")
            }
            .accessibilityLabel("Close \(mode)")
          }
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 4)
        .foregroundStyle(NativeTheme.ink)
        .background(NativeTheme.leaf, in: Capsule())
        .shadow(color: NativeTheme.ink.opacity(0.18), radius: 9, y: 3)
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.top, 8)
        .padding(.horizontal, 80)
      }
    }
    .onDrop(
      of: [notebookSelectionDragType, .plainText],
      delegate: NotebookEditorDropDelegate(
        canDrop: { !drawing },
        onFocus: onFocus,
        onDropClipping: onDropClipping,
        onDropSelection: onDropSelection))
    .simultaneousGesture(
      TapGesture().onEnded { onFocus() })
    .onChange(of: documentRevision) {
      normalizeViewState()
    }
    .onChange(of: tool) {
      if bookmarkMode { bookmarkMode = false }
    }
    .overlay(alignment: .bottomTrailing) {
      let count = (try? document.pageCount()) ?? 1
      let text = editorPageCounterText(currentPage: currentPage, pageCount: count)
      Text(text)
        .font(NativeTheme.callout)
        .foregroundStyle(NativeTheme.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(NativeTheme.board, in: RoundedRectangle(cornerRadius: 12))
        .allowsHitTesting(false)
        .accessibilityLabel("Page \(text.replacingOccurrences(of: " / ", with: " of "))")
        .padding(12)
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
    .onChange(of: tool) { old, next in
      if old != next, old != .navigate {
        previousPencilTool = old
      }
    }
  }

  private var modeBannerLabel: String? {
    if drawing { return "Drawing mode" }
    if bookmarkMode { return "Add bookmark" }
    return switch tool {
    case .space: "Insert space"
    case .text: "Text"
    case .navigate: "Follow links"
    default: nil
    }
  }

  private func toggleDrawingMode() {
    if !drawing, ![EditorTool.pen, .marker, .highlighter].contains(tool) {
      tool = .pen
    }
    pageCommand = .toggleFigureCapture(currentPage)
  }

  private func closeModeBanner() {
    if bookmarkMode {
      bookmarkMode = false
    } else {
      tool = drawingTool
    }
  }

  private func applyPencilAction(_ action: UIPencilPreferredAction) {
    switch action {
    case .switchEraser:
      if tool == .eraser, let previousPencilTool, previousPencilTool != .eraser {
        let current = tool
        tool = previousPencilTool
        self.previousPencilTool = current
      } else if tool != .eraser {
        let current = tool
        tool = .eraser
        previousPencilTool = current
      }
    case .switchPrevious:
      guard let previousPencilTool, previousPencilTool != tool else { return }
      let current = tool
      tool = previousPencilTool
      self.previousPencilTool = current
    default:
      break
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
  private func history(redo: Bool) -> Bool {
    guard !drawing else { return false }
    do {
      let step: EngineHistoryStep?
      if redo {
        step = try document.redo()
      } else {
        step = try document.undo()
      }
      guard let step else { return false }
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
      return true
    } catch {
      onError(error)
      return false
    }
  }
}
