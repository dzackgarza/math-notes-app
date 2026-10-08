import InkEngine
import MJRefresh
import QuartzCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

private let notebookSelectionDragType = UTType(
  exportedAs: "dev.zack.mathnotes.selection-drag")
let notebookSelectionCopyDragType = UTType(
  exportedAs: "dev.zack.mathnotes.selection-copy-drag")
let notebookClippingDragType = UTType(
  exportedAs: "dev.zack.mathnotes.clipping-drag")

@MainActor
private struct NotebookEditorDropDelegate: DropDelegate {
  let canDrop: () -> Bool
  let onFocus: () -> Void
  let onDropClipping: (String, CGPoint) -> Bool

  func dropUpdated(info: DropInfo) -> DropProposal? {
    DropProposal(operation: .copy)
  }

  func validateDrop(info: DropInfo) -> Bool {
    canDrop() && info.hasItemsConforming(to: [notebookClippingDragType])
  }

  func performDrop(info: DropInfo) -> Bool {
    guard canDrop(),
      let provider = info.itemProviders(for: [notebookClippingDragType]).first
    else { return false }
    onFocus()
    let location = info.location
    provider.loadDataRepresentation(
      forTypeIdentifier: notebookClippingDragType.identifier
    ) { data, _ in
      guard let data, let id = String(data: data, encoding: .utf8) else { return }
      Task { @MainActor in
        _ = onDropClipping(id, location)
      }
    }
    return true
  }
}

func alignmentFeedbackNeeded(previous: Int?, current: Int) -> Bool {
  previous != current
}

func editorDocumentMutationAllowed(
  figureCaptureActive: Bool,
  figureCompleting: Bool
) -> Bool {
  !figureCaptureActive && !figureCompleting
}

func editorKeyboardEditingAllowed(
  active: Bool,
  focused: Bool,
  figureCaptureActive: Bool,
  figureCompleting: Bool
) -> Bool {
  active && focused && editorDocumentMutationAllowed(
    figureCaptureActive: figureCaptureActive,
    figureCompleting: figureCompleting)
}

func pencilHoverPreviewAllowed(
  preference: Bool,
  hostActive: Bool,
  hostFocused: Bool,
  pencilStrokeActive: Bool
) -> Bool {
  preference && hostActive && hostFocused && !pencilStrokeActive
}

struct PencilPreferredActionResult: Equatable {
  var tool: EditorTool
  var previousTool: EditorTool?
  var paletteAnchor: CGPoint?
}

func applyPreferredPencilAction(
  _ action: UIPencilPreferredAction,
  tool: EditorTool,
  previousTool: EditorTool?,
  point: CGPoint?
) -> PencilPreferredActionResult {
  var result = PencilPreferredActionResult(
    tool: tool, previousTool: previousTool, paletteAnchor: nil)
  switch action {
  case .switchEraser:
    if tool == .eraser, let previousTool, previousTool != .eraser {
      result.tool = previousTool
      result.previousTool = tool
    } else if tool != .eraser {
      result.tool = .eraser
      result.previousTool = tool
    }
  case .switchPrevious:
    if let previousTool, previousTool != tool {
      result.tool = previousTool
      result.previousTool = tool
    }
  case .showColorPalette, .showContextualPalette:
    result.paletteAnchor = point ?? CGPoint(x: 88, y: 88)
  default:
    break
  }
  return result
}

enum EditorPageCommand: Equatable {
  indirect case identified(UUID, EditorPageCommand)

  var action: EditorPageCommand {
    switch self {
    case let .identified(_, command): command.action
    default: self
    }
  }

  var isIdentified: Bool {
    switch self {
    case .identified: true
    default: false
    }
  }
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
final class InkEditorViewController: UIViewController, UIScrollViewDelegate, UIEditMenuInteractionDelegate, UIDragInteractionDelegate, UIDropInteractionDelegate, UIPencilInteractionDelegate {
  private static let deskMargin: CGFloat = 16
  private static let toolRailInset: CGFloat = 8
  private static let toolRailWidth: CGFloat = 60
  private static let deskLeadingMargin = toolRailInset + toolRailWidth + deskMargin

  private let document: EngineDocument
  private let scrollView = UIScrollView()
  private let documentView = UIView()
  private let onFocusRequested: () -> Void
  private let onViewportChanged: (EditorLinkedViewport) -> Void
  private let onFitStateChanged: (Bool) -> Void
  private let onEditCommitted: () -> Void
  private let onSaveRequested: () -> Void
  private let onInsertImageRequested: () -> Void
  private let onShowClippingsRequested: () -> Void
  private let onCurrentPageChanged: (Int) -> Void
  private let onPageCommandHandled: (EditorPageCommand, Bool) -> Void
  private let onBookmarkModeChanged: (Bool) -> Void
  private let onTextRequested: (EditorTextRequest) -> Void
  private let onLinkSelectionRequested: (Int) -> Void
  private let onFollowLink: (String, Int) -> Void
  private let onSaveClipping: (String) -> Void
  private let onSelectionChanged: (Bool) -> Void
  private let onUndo: () -> Void
  private let onRedo: () -> Void
  private let onPencilAction: (UIPencilPreferredAction, CGPoint?) -> Void
  private let onFigureCaptureChanged: (Bool) -> Void
  private let onFigureSourceChanged: (String) -> Void
  private let onEditFigure: (String) -> Void
  private let onError: (Error) -> Void
  private lazy var canvasView = InkCanvasView(
    document: document,
    onInteractionBegan: { [weak self] in
      self?.canvasInteractionBegan()
    },
    onInteractionChanged: { [weak self] point in self?.canvasInteractionChanged(at: point) },
    onInteractionEnded: { [weak self] in self?.canvasInteractionEnded() },
    onPencilStrokeChanged: { [weak self] active in
      self?.setPencilStrokeActive(active)
    })
  private let selectionBar = SelectionActionWrapView(spacing: 2, contentInset: 2)
  private let pencilHoverIndicator = UIView()
  private var editFigureButton: UIButton?
  private var saveClippingButton: UIButton?
  private var selectionCopyDragHandle: UIButton?
  private var dragSelectionFrame: CGRect?
  private var dragSelectionSVG: String?
  private var dragSelectionPage: Int?
  private var dragDocumentRevision: Int?
  private var clippingsPanelOpen = false
  private let figureGenerator = FigureTikZGenerator()
  private var canvasFeedback: UICanvasFeedbackGenerator?
  private var figureCaptureActive = false
  private var figureCompleting = false
  private var figurePreviewGeneration = 0
  private var reportedFigureID: String?
  private var reportedSelectionActive = false
  private var lastAlignmentStep: Int?
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
  private var fingerDrawing = false
  private var pencilStrokeActive = false
  private var pageEditMenuInteraction: UIEditMenuInteraction?
  private var pageLongPress: UILongPressGestureRecognizer?
  private var directTap: UITapGestureRecognizer?
  private var undoTap: UITapGestureRecognizer?
  private var redoTap: UITapGestureRecognizer?
  private var applyingLinkedViewport = false
  private var lastAppliedLinkedViewport: EditorLinkedViewport?
  private var requestedLinkedViewport: EditorLinkedViewport?
  private var lastLayoutSize = CGSize.zero
  private var reportedPage = -1
  private var reportedFitActive: Bool?

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
    onFitStateChanged: @escaping (Bool) -> Void = { _ in },
    onEditCommitted: @escaping () -> Void = {},
    onSaveRequested: @escaping () -> Void = {},
    onInsertImageRequested: @escaping () -> Void = {},
    onShowClippingsRequested: @escaping () -> Void = {},
    onCurrentPageChanged: @escaping (Int) -> Void = { _ in },
    onPageCommandHandled: @escaping (EditorPageCommand, Bool) -> Void = { _, _ in },
    onBookmarkModeChanged: @escaping (Bool) -> Void = { _ in },
    onTextRequested: @escaping (EditorTextRequest) -> Void = { _ in },
    onLinkSelectionRequested: @escaping (Int) -> Void = { _ in },
    onFollowLink: @escaping (String, Int) -> Void = { _, _ in },
    onSaveClipping: @escaping (String) -> Void = { _ in },
    onSelectionChanged: @escaping (Bool) -> Void = { _ in },
    onUndo: @escaping () -> Void = {},
    onRedo: @escaping () -> Void = {},
    onPencilAction: @escaping (UIPencilPreferredAction, CGPoint?) -> Void = { _, _ in },
    onFigureCaptureChanged: @escaping (Bool) -> Void = { _ in },
    onFigureSourceChanged: @escaping (String) -> Void = { _ in },
    onEditFigure: @escaping (String) -> Void = { _ in },
    onError: @escaping (Error) -> Void = { _ in }
  ) {
    self.document = document
    self.onFocusRequested = onFocusRequested
    self.onViewportChanged = onViewportChanged
    self.onFitStateChanged = onFitStateChanged
    self.onEditCommitted = onEditCommitted
    self.onSaveRequested = onSaveRequested
    self.onInsertImageRequested = onInsertImageRequested
    self.onShowClippingsRequested = onShowClippingsRequested
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
      editorKeyCommand(UIKeyCommand.inputEscape, modifiers: [], action: #selector(keyboardEscape), title: "Cancel Drawing or Selection"),
      editorKeyCommand("s", modifiers: .command, action: #selector(keyboardSave), title: "Save"),
      editorKeyCommand(UIKeyCommand.inputUpArrow, modifiers: .command, action: #selector(keyboardPreviousPage), title: "Previous Page"),
      editorKeyCommand(UIKeyCommand.inputDownArrow, modifiers: .command, action: #selector(keyboardNextPage), title: "Next Page"),
      editorKeyCommand(UIKeyCommand.inputLeftArrow, modifiers: .command, action: #selector(keyboardPreviousHorizontalPage), title: "Previous Horizontal Page"),
      editorKeyCommand(UIKeyCommand.inputRightArrow, modifiers: .command, action: #selector(keyboardNextHorizontalPage), title: "Next Horizontal Page"),
      editorKeyCommand(UIKeyCommand.inputUpArrow, modifiers: [.command, .alternate], action: #selector(keyboardFirstPage), title: "First Page"),
      editorKeyCommand(UIKeyCommand.inputDownArrow, modifiers: [.command, .alternate], action: #selector(keyboardLastPage), title: "Last Page"),
      editorKeyCommand("0", modifiers: .command, action: #selector(keyboardFitPages), title: "Fit Pages"),
      editorKeyCommand("=", modifiers: .command, action: #selector(keyboardZoomIn), title: "Zoom In"),
      editorKeyCommand("-", modifiers: .command, action: #selector(keyboardZoomOut), title: "Zoom Out"),
      editorKeyCommand("i", modifiers: .command, action: #selector(keyboardInsertImage), title: "Insert Image"),
      editorKeyCommand("k", modifiers: .command.union(.shift), action: #selector(keyboardClippings), title: "Clippings"),
      editorKeyCommand("c", modifiers: .command.union(.shift), action: #selector(keyboardSaveClipping), title: "Save Clipping"),
      editorKeyCommand("b", modifiers: .command.union(.shift), action: #selector(keyboardBookmarkSelection), title: "Bookmark Selection"),
      editorKeyCommand("l", modifiers: .command.union(.shift), action: #selector(keyboardLinkSelection), title: "Link Selection"),
      editorKeyCommand("u", modifiers: .command.union(.shift), action: #selector(keyboardUngroupSelection), title: "Remove Bookmark or Link"),
      editorKeyCommand("z", modifiers: .command, action: #selector(keyboardUndo), title: "Undo"),
      editorKeyCommand(
        "z",
        modifiers: .command.union(.shift),
        action: #selector(keyboardRedo),
        title: "Redo"),
      editorKeyCommand("y", modifiers: .command, action: #selector(keyboardRedo), title: "Redo"),
      editorKeyCommand("a", modifiers: .command, action: #selector(keyboardSelectAll), title: "Select All"),
      editorKeyCommand("c", modifiers: .command, action: #selector(keyboardCopy), title: "Copy"),
      editorKeyCommand("x", modifiers: .command, action: #selector(keyboardCut), title: "Cut"),
      editorKeyCommand("v", modifiers: .command, action: #selector(keyboardPaste), title: "Paste"),
      editorKeyCommand("d", modifiers: .command, action: #selector(keyboardDuplicate), title: "Duplicate"),
      editorKeyCommand(
        UIKeyCommand.inputDelete,
        modifiers: [],
        action: #selector(keyboardDelete),
        title: "Delete Selection"),
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
    canvasFeedback = UICanvasFeedbackGenerator(view: canvasView)

    pencilHoverIndicator.isHidden = true
    pencilHoverIndicator.isUserInteractionEnabled = false
    pencilHoverIndicator.layer.borderWidth = 1.5
    pencilHoverIndicator.accessibilityElementsHidden = true
    view.addSubview(pencilHoverIndicator)

    let pencilHover = UIHoverGestureRecognizer(target: self, action: #selector(handlePencilHover))
    pencilHover.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
    canvasView.addGestureRecognizer(pencilHover)

    configureBottomPull()
    configureSelectionBar()
    let editMenuInteraction = UIEditMenuInteraction(delegate: self)
    pageEditMenuInteraction = editMenuInteraction
    canvasView.addInteraction(editMenuInteraction)
    let pageLongPress = UILongPressGestureRecognizer(target: self, action: #selector(handlePageLongPress))
    pageLongPress.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
    self.pageLongPress = pageLongPress
    canvasView.addGestureRecognizer(pageLongPress)
    let secondaryClick = UITapGestureRecognizer(target: self, action: #selector(handlePageSecondaryClick))
    secondaryClick.buttonMaskRequired = .secondary
    canvasView.addGestureRecognizer(secondaryClick)
    canvasView.addInteraction(UIDragInteraction(delegate: self))
    canvasView.addInteraction(UIDropInteraction(delegate: self))
    let directTap = UITapGestureRecognizer(target: self, action: #selector(handleDirectTap))
    self.directTap = directTap
    directTap.cancelsTouchesInView = false
    directTap.buttonMaskRequired = .primary
    directTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
    canvasView.addGestureRecognizer(directTap)

    let pencilTap = UITapGestureRecognizer(target: self, action: #selector(handlePencilModeTap))
    pencilTap.cancelsTouchesInView = false
    pencilTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
    canvasView.addGestureRecognizer(pencilTap)

    let undoTap = UITapGestureRecognizer(target: self, action: #selector(handleUndoTap))
    self.undoTap = undoTap
    undoTap.cancelsTouchesInView = false
    undoTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
    undoTap.numberOfTouchesRequired = 2
    canvasView.addGestureRecognizer(undoTap)

    let redoTap = UITapGestureRecognizer(target: self, action: #selector(handleRedoTap))
    self.redoTap = redoTap
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
    reportFitState()
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
    if !active || !focused { pencilHoverIndicator.isHidden = true }
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
      reportedFigureID = nil
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

  func setPencilStrokeActive(_ active: Bool) {
    pencilStrokeActive = active
    if active { pencilHoverIndicator.isHidden = true }
    scrollView.panGestureRecognizer.isEnabled = !active
    scrollView.pinchGestureRecognizer?.isEnabled = !active
    pageLongPress?.isEnabled = !active && !fingerDrawing
    directTap?.isEnabled = !active
    undoTap?.isEnabled = !active
    redoTap?.isEnabled = !active
    if active { pageEditMenuInteraction?.dismissMenu() }
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
    reportFitState()
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
      editorDocumentMutationAllowed(
        figureCaptureActive: figureCaptureActive,
        figureCompleting: figureCompleting) &&
      addPageFooter.state == .pulling &&
      pullGate.release(at: CACurrentMediaTime())
    cancelPullReadyTimer()
  }

  func dragInteraction(
    _ interaction: UIDragInteraction,
    itemsForBeginning session: UIDragSession
  ) -> [UIDragItem] {
    guard hostActive else { return [] }
    onFocusRequested()
    let copyHandle = interaction.view === selectionCopyDragHandle
    guard !pencilStrokeActive else { return [] }
    guard !fingerDrawing || copyHandle else { return [] }
    guard !figureCaptureActive, !figureCompleting else { return [] }
    if !copyHandle {
      let location = session.location(in: canvasView)
      guard let selection = canvasView.selectionFrame(), selection.contains(location) else { return [] }
    }
    do {
      guard let svg = try canvasView.copySelection(), !svg.isEmpty else { return [] }
      dragSelectionSVG = svg
      dragSelectionFrame = canvasView.selectionFrame()
      dragSelectionPage = canvasView.selectionPage()
      dragDocumentRevision = documentRevision
      let provider = NSItemProvider(object: svg as NSString)
      provider.registerDataRepresentation(
        forTypeIdentifier: notebookSelectionCopyDragType.identifier,
        visibility: .ownProcess
      ) { completion in
        completion(Data(svg.utf8), nil)
        return nil
      }
      provider.registerDataRepresentation(
        forTypeIdentifier: UTType.svg.identifier,
        visibility: .all
      ) { completion in
        completion(Data(svg.utf8), nil)
        return nil
      }
      if !copyHandle {
        provider.registerDataRepresentation(
          forTypeIdentifier: notebookSelectionDragType.identifier,
          visibility: .ownProcess
        ) { completion in
          completion(Data(svg.utf8), nil)
          return nil
        }
      }
      let item = UIDragItem(itemProvider: provider)
      item.localObject = self
      return [item]
    } catch {
      onError(error)
      return []
    }
  }

  func dragInteraction(
    _ interaction: UIDragInteraction,
    session: UIDragSession,
    didEndWith operation: UIDropOperation
  ) {
    dragSelectionFrame = nil
    dragSelectionSVG = nil
    dragSelectionPage = nil
    dragDocumentRevision = nil
  }

  func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
    guard hostActive, !figureCaptureActive, !figureCompleting, session.items.count == 1,
      let item = session.items.first
    else { return false }
    guard canvasView.page(at: session.location(in: canvasView)) != nil else { return false }
    if let source = item.localObject as? InkEditorViewController {
      return source.hostActive && source.dragSelectionSVG != nil &&
        source.dragSelectionFrame != nil && source.dragSelectionPage != nil &&
        source.dragDocumentRevision == source.documentRevision
    }
    return [notebookSelectionCopyDragType, .svg, .utf8PlainText, .plainText, .png, .jpeg, .heic, .heif, .tiff].contains {
      item.itemProvider.hasItemConformingToTypeIdentifier($0.identifier)
    } || item.itemProvider.canLoadObject(ofClass: UIImage.self) ||
      item.itemProvider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
  }

  func dropInteraction(
    _ interaction: UIDropInteraction,
    sessionDidUpdate session: UIDropSession
  ) -> UIDropProposal {
    guard dropInteraction(interaction, canHandle: session) else {
      return UIDropProposal(operation: .cancel)
    }
    let item = session.items[0]
    let movable = item.itemProvider.hasItemConformingToTypeIdentifier(notebookSelectionDragType.identifier)
    let local = item.localObject is InkEditorViewController
    return UIDropProposal(operation: local && movable && session.allowsMoveOperation ? .move : .copy)
  }

  func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
    guard dropInteraction(interaction, canHandle: session), let item = session.items.first else { return }
    onFocusRequested()
    if !(item.localObject is InkEditorViewController) {
      let point = session.location(in: canvasView)
      guard let destinationPage = canvasView.page(at: point) else { return }
      let destinationRevision = documentRevision
      let provider = item.itemProvider
      if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) &&
        ![notebookSelectionCopyDragType, .svg, .utf8PlainText, .plainText, .png, .jpeg, .heic, .heif, .tiff].contains(where: {
          provider.hasItemConformingToTypeIdentifier($0.identifier)
        }) {
        _ = provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, _ in
          let url: URL?
          switch item {
          case let value as URL:
            url = value
          case let value as Data:
            url = URL(dataRepresentation: value, relativeTo: nil)
          case let value as String:
            url = URL(string: value)
          default:
            url = nil
          }
          guard let url, url.isFileURL else { return }
          let scoped = url.startAccessingSecurityScopedResource()
          let data = try? Data(contentsOf: url)
          if scoped { url.stopAccessingSecurityScopedResource() }
          guard let data else { return }
          Task { @MainActor [weak self] in
            guard let self, self.hostActive, !self.figureCaptureActive, !self.figureCompleting,
              self.documentRevision == destinationRevision,
              self.canvasView.page(at: point) == destinationPage
            else { return }
            do {
              let svg: String
              if url.pathExtension.lowercased() == "svg" {
                guard let decoded = String(data: data, encoding: .utf8), decoded.contains("<svg") else { return }
                svg = decoded
              } else {
                guard let image = UIImage(data: data)?.cgImage else { return }
                let ext = url.pathExtension.lowercased()
                guard ["png", "jpg", "jpeg", "heic", "heif", "tif", "tiff"].contains(ext) else { return }
                let importedData: Data
                let mimeType: String
                switch ext {
                case "png":
                  importedData = data
                  mimeType = "image/png"
                case "jpg", "jpeg":
                  importedData = data
                  mimeType = "image/jpeg"
                default:
                  guard let png = UIImage(cgImage: image).pngData() else { return }
                  importedData = png
                  mimeType = "image/png"
                }
                let pageSize = try self.document.pageRect(index: destinationPage).size
                svg = try imageImportSVG(
                  data: importedData, mimeType: mimeType,
                  imageSize: CGSize(width: image.width, height: image.height), pageSize: pageSize)
              }
              try self.canvasView.paste(svg, at: point, placeAtPointer: true)
              self.onEditCommitted()
              self.refreshSelectionBar()
            } catch { self.onError(error) }
          }
        }
        return
      }
      if ![notebookSelectionCopyDragType, .svg, .utf8PlainText, .plainText, .png, .jpeg, .heic, .heif, .tiff].contains(where: {
        provider.hasItemConformingToTypeIdentifier($0.identifier)
      }) {
        _ = provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
          guard let image = object as? UIImage, let data = image.pngData() else { return }
          Task { @MainActor [weak self] in
            guard let self, self.hostActive, !self.figureCaptureActive, !self.figureCompleting,
              self.documentRevision == destinationRevision,
              self.canvasView.page(at: point) == destinationPage,
              let cgImage = UIImage(data: data)?.cgImage
            else { return }
            do {
              let pageSize = try self.document.pageRect(index: destinationPage).size
              let svg = try imageImportSVG(
                data: data, mimeType: "image/png",
                imageSize: CGSize(width: cgImage.width, height: cgImage.height),
                pageSize: pageSize)
              try self.canvasView.paste(svg, at: point, placeAtPointer: true)
              self.onEditCommitted()
              self.refreshSelectionBar()
            } catch {
              self.onError(error)
            }
          }
        }
        return
      }
      let copyType: UTType
      if item.itemProvider.hasItemConformingToTypeIdentifier(notebookSelectionCopyDragType.identifier) {
        copyType = notebookSelectionCopyDragType
      } else if item.itemProvider.hasItemConformingToTypeIdentifier(UTType.svg.identifier) {
        copyType = .svg
      } else if item.itemProvider.hasItemConformingToTypeIdentifier(UTType.png.identifier) {
        copyType = .png
      } else if item.itemProvider.hasItemConformingToTypeIdentifier(UTType.jpeg.identifier) {
        copyType = .jpeg
      } else if let rasterType = [UTType.heic, .heif, .tiff].first(where: {
        item.itemProvider.hasItemConformingToTypeIdentifier($0.identifier)
      }) {
        copyType = rasterType
      } else if item.itemProvider.hasItemConformingToTypeIdentifier(UTType.utf8PlainText.identifier) {
        copyType = .utf8PlainText
      } else {
        copyType = .plainText
      }
      item.itemProvider.loadDataRepresentation(
        forTypeIdentifier: copyType.identifier
      ) { [weak self] data, _ in
        guard let data else { return }
        Task { @MainActor [weak self] in
          guard let self, self.hostActive, !self.figureCaptureActive, !self.figureCompleting,
            self.documentRevision == destinationRevision,
            self.canvasView.page(at: point) == destinationPage
          else { return }
          do {
            let svg: String
            if [.png, .jpeg, .heic, .heif, .tiff].contains(copyType) {
              guard let image = UIImage(data: data)?.cgImage else { return }
              let pageSize = try self.document.pageRect(index: destinationPage).size
              let importedData: Data
              let mimeType: String
              switch copyType {
              case .png:
                importedData = data
                mimeType = "image/png"
              case .jpeg:
                importedData = data
                mimeType = "image/jpeg"
              default:
                guard let png = UIImage(cgImage: image).pngData() else { return }
                importedData = png
                mimeType = "image/png"
              }
              svg = try imageImportSVG(
                data: importedData, mimeType: mimeType,
                imageSize: CGSize(width: image.width, height: image.height),
                pageSize: pageSize)
            } else {
              guard let decoded = String(data: data, encoding: .utf8), decoded.contains("<svg") else { return }
              svg = decoded
            }
            try self.canvasView.paste(svg, at: point, placeAtPointer: true)
            self.onEditCommitted()
            self.refreshSelectionBar()
          } catch {
            self.onError(error)
          }
        }
      }
      return
    }
    guard let source = item.localObject as? InkEditorViewController,
      source.hostActive,
      let originalFrame = source.dragSelectionFrame,
      let originalPage = source.dragSelectionPage,
      source.dragDocumentRevision == source.documentRevision,
      source.canvasView.selectionPage() == originalPage,
      source.canvasView.selectionFrame() == originalFrame
    else { return }
    let point = session.location(in: canvasView)
    let movable = item.itemProvider.hasItemConformingToTypeIdentifier(notebookSelectionDragType.identifier)
    do {
      if movable && session.allowsMoveOperation && source.document === document {
        let contentPoint = documentView.convert(point, from: canvasView)
        let sourcePoint = source.canvasView.convert(contentPoint, from: source.documentView)
        try source.canvasView.moveSelection(to: sourcePoint)
        source.onEditCommitted()
        source.refreshSelectionBar()
      } else {
        guard let svg = source.dragSelectionSVG else { return }
        try canvasView.paste(svg, at: point, placeAtPointer: true)
        if movable && session.allowsMoveOperation && source.document !== document {
          guard source.hostActive,
            source.dragDocumentRevision == source.documentRevision,
            source.canvasView.selectionFrame() == originalFrame,
            source.canvasView.selectionPage() == originalPage
          else {
            _ = try document.undo()
            onEditCommitted()
            refreshSelectionBar()
            return
          }
          do {
            try source.canvasView.deleteSelection()
          } catch {
            _ = try document.undo()
            onEditCommitted()
            refreshSelectionBar()
            throw error
          }
          source.onEditCommitted()
          source.refreshSelectionBar()
        }
        onEditCommitted()
        refreshSelectionBar()
      }
    } catch {
      onError(error)
    }
  }

  @objc private func handlePageLongPress(_ recognizer: UILongPressGestureRecognizer) {
    guard recognizer.state == .began, !fingerDrawing,
      hostActive, hostFocused, !figureCaptureActive, !figureCompleting,
      let pageEditMenuInteraction
    else { return }
    onFocusRequested()
    pageEditMenuInteraction.presentEditMenu(
      with: UIEditMenuConfiguration(
        identifier: nil,
        sourcePoint: recognizer.location(in: canvasView)))
  }

  @objc private func handlePageSecondaryClick(_ recognizer: UITapGestureRecognizer) {
    guard recognizer.state == .ended, !figureCaptureActive, !figureCompleting,
      hostActive, hostFocused, let pageEditMenuInteraction
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
    guard hostActive, hostFocused, !figureCaptureActive, !figureCompleting else { return nil }
    onFocusRequested()
    let location = configuration.sourcePoint
    let pressedPage = canvasView.page(at: location)
    guard pressedPage != nil || canvasView.selectionFrame() != nil else { return nil }
    let svg = selectionFromPasteboard()
    let selectedPage = canvasView.selectionPage()
    let selectedFrame = canvasView.selectionFrame()
    let menuRevision = documentRevision
    let canSaveClipping = canvasView.selectionFrame() != nil &&
      (pressedPage == nil || selectedPage == pressedPage)
    var actions: [UIMenuElement] = []
    if pressedPage != nil && ((svg?.contains("<svg") == true) ||
      UIPasteboard.general.data(forPasteboardType: UTType.png.identifier) != nil ||
      UIPasteboard.general.data(forPasteboardType: UTType.jpeg.identifier) != nil ||
      UIPasteboard.general.data(forPasteboardType: UTType.heic.identifier) != nil ||
      UIPasteboard.general.data(forPasteboardType: UTType.heif.identifier) != nil ||
      UIPasteboard.general.data(forPasteboardType: UTType.tiff.identifier) != nil ||
      UIPasteboard.general.image != nil) {
      actions.append(UIAction(
        title: "Paste",
        image: UIImage(systemName: "doc.on.clipboard")
      ) { [weak self] _ in
        guard let self, self.keyboardEditingAllowed,
          self.documentRevision == menuRevision,
          self.canvasView.page(at: location) == pressedPage
        else { return }
        self.pasteFromPasteboard(at: location, placeAtPointer: true)
      })
    }
    if pressedPage != nil {
      actions.append(UIAction(
        title: "Insert Image or SVG",
        image: UIImage(systemName: "photo.on.rectangle")
      ) { [weak self] _ in
        self?.onInsertImageRequested()
      })
    }
    if let page = pressedPage {
      actions.append(UIAction(title: "Select All on Page", image: UIImage(systemName: "selection.pin.in.out")) { [weak self] _ in
        guard let self, self.keyboardEditingAllowed,
          self.documentRevision == menuRevision,
          self.canvasView.page(at: location) == page
        else { return }
        do {
          try self.canvasView.selectAll(page: page)
          self.refreshSelectionBar()
        } catch {
          self.onError(error)
        }
      })
    }
    if let page = pressedPage {
      actions.append(UIAction(
        title: "Clear Page", image: UIImage(systemName: "eraser"), attributes: .destructive
      ) { [weak self] _ in
        guard let self, self.keyboardEditingAllowed,
          self.documentRevision == menuRevision, self.canvasView.page(at: location) == page
        else { return }
        do {
          try self.canvasView.selectAll(page: page)
          try self.canvasView.deleteSelection()
          self.onEditCommitted()
          self.refreshSelectionBar()
        } catch {
          self.onError(error)
        }
      })
    }
    if let page = pressedPage {
      actions.append(UIAction(title: "Add Bookmark Here", image: UIImage(systemName: "bookmark.fill")) { [weak self] _ in
        guard let self, self.keyboardEditingAllowed,
          self.documentRevision == menuRevision, self.canvasView.page(at: location) == page
        else { return }
        do {
          try self.canvasView.addBookmark(at: location)
          self.onEditCommitted()
          self.refreshSelectionBar()
        } catch {
          self.onError(error)
        }
      })
    }
    if canSaveClipping {
      actions.append(UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in
        guard let self, self.keyboardEditingAllowed,
          self.documentRevision == menuRevision,
          self.canvasView.selectionPage() == selectedPage,
          self.canvasView.selectionFrame() == selectedFrame
        else { return }
        self.copySelection()
      })
      actions.append(UIAction(title: "Cut", image: UIImage(systemName: "scissors")) { [weak self] _ in
        guard let self, self.keyboardEditingAllowed,
          self.documentRevision == menuRevision,
          self.canvasView.selectionPage() == selectedPage,
          self.canvasView.selectionFrame() == selectedFrame
        else { return }
        self.cutSelection()
      })
      actions.append(UIAction(title: "Duplicate", image: UIImage(systemName: "plus.square.on.square")) { [weak self] _ in
        guard let self, self.keyboardEditingAllowed,
          self.documentRevision == menuRevision,
          self.canvasView.selectionPage() == selectedPage,
          self.canvasView.selectionFrame() == selectedFrame
        else { return }
        self.duplicateSelection()
      })
      actions.append(UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
        guard let self, self.keyboardEditingAllowed,
          self.documentRevision == menuRevision,
          self.canvasView.selectionPage() == selectedPage,
          self.canvasView.selectionFrame() == selectedFrame
        else { return }
        self.deleteSelection()
      })
    }
    if canSaveClipping {
      actions.append(UIAction(title: "Link", image: UIImage(systemName: "link")) { [weak self] _ in
        guard let self, self.keyboardEditingAllowed,
          self.documentRevision == menuRevision,
          self.canvasView.selectionPage() == selectedPage,
          self.canvasView.selectionFrame() == selectedFrame
        else { return }
        self.linkSelection()
      })
      actions.append(UIAction(title: "Bookmark", image: UIImage(systemName: "bookmark")) { [weak self] _ in
        guard let self, self.keyboardEditingAllowed,
          self.documentRevision == menuRevision,
          self.canvasView.selectionPage() == selectedPage,
          self.canvasView.selectionFrame() == selectedFrame
        else { return }
        self.bookmarkSelection()
      })
      actions.append(UIAction(title: "Remove bookmark or link", image: UIImage(systemName: "link.badge.minus")) { [weak self] _ in
        guard let self, self.keyboardEditingAllowed,
          self.documentRevision == menuRevision,
          self.canvasView.selectionPage() == selectedPage,
          self.canvasView.selectionFrame() == selectedFrame
        else { return }
        self.ungroupSelection()
      })
      actions.append(UIAction(title: "Clear selection", image: UIImage(systemName: "xmark")) { [weak self] _ in
        guard let self, self.keyboardEditingAllowed,
          self.documentRevision == menuRevision,
          self.canvasView.selectionPage() == selectedPage,
          self.canvasView.selectionFrame() == selectedFrame
        else { return }
        self.clearSelection()
      })
    }
    if let page = pressedPage, canvasView.selectionFrame() == nil {
      actions.append(UIAction(
        title: "Save Page to Clippings",
        image: UIImage(systemName: "tray.and.arrow.down")
      ) { [weak self] _ in
        guard let self, self.keyboardEditingAllowed,
          self.documentRevision == menuRevision, self.canvasView.page(at: location) == page
        else { return }
        do {
          try self.canvasView.selectAll(page: page)
          defer {
            try? self.canvasView.clearSelection()
            self.refreshSelectionBar()
          }
          if let svg = try self.canvasView.copySelection(), !svg.isEmpty {
            self.onSaveClipping(svg)
          }
        } catch {
          self.onError(error)
        }
      })
    }
    if canSaveClipping {
      actions.append(UIAction(
        title: "Save to clippings",
        image: UIImage(systemName: "tray.and.arrow.down")
      ) { [weak self] _ in
        guard let self, self.keyboardEditingAllowed,
          self.documentRevision == menuRevision,
          self.canvasView.selectionPage() == selectedPage,
          self.canvasView.selectionFrame() == selectedFrame
        else { return }
        self.saveClipping()
      })
    }
    if canSaveClipping, (try? canvasView.selectedFigure()) != nil {
      actions.append(UIAction(
        title: "Edit figure",
        image: UIImage(systemName: "scribble.variable")
      ) { [weak self] _ in
        guard let self, self.keyboardEditingAllowed,
          self.documentRevision == menuRevision,
          self.canvasView.selectionPage() == selectedPage,
          self.canvasView.selectionFrame() == selectedFrame
        else { return }
        self.editSelectedFigure()
      })
    }
    return UIMenu(children: actions)
  }
  private func configureSelectionBar() {
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

    let dragCopy = selectionMenuButton(label: "Drag a copy", systemImage: "hand.draw")
    dragCopy.addInteraction(UIDragInteraction(delegate: self))
    selectionCopyDragHandle = dragCopy
    selectionBar.addArrangedSubview(dragCopy)
    selectionBar.addArrangedSubview(selectionButton(
      label: "Copy", systemImage: "doc.on.doc", action: #selector(copySelection)))
    selectionBar.addArrangedSubview(selectionButton(
      label: "Cut", systemImage: "scissors", action: #selector(cutSelection)))
    selectionBar.addArrangedSubview(selectionButton(
      label: "Duplicate", systemImage: "plus.square.on.square", action: #selector(duplicateSelection)))
    let deleteSelection = selectionButton(
      label: "Delete selection", systemImage: "trash", action: #selector(deleteSelection))
    deleteSelection.tintColor = NativeTheme.ribbonUI
    selectionBar.addArrangedSubview(deleteSelection)
    selectionBar.addArrangedSubview(selectionButton(
      label: "Link selected content", systemImage: "link", action: #selector(linkSelection)))
    selectionBar.addArrangedSubview(selectionButton(
      label: "Bookmark selection", systemImage: "bookmark", action: #selector(bookmarkSelection)))
    selectionBar.addArrangedSubview(selectionButton(
      label: "Remove bookmark or link", systemImage: "link.badge.minus", action: #selector(ungroupSelection)))
    let saveClipping = selectionButton(
      label: "Save to clippings", systemImage: "tray.and.arrow.down", action: #selector(saveClipping))
    saveClipping.isHidden = true
    saveClippingButton = saveClipping
    selectionBar.addArrangedSubview(saveClipping)
    let editFigure = selectionButton(
      label: "Edit figure", systemImage: "scribble.variable", action: #selector(editSelectedFigure))
    editFigureButton = editFigure
    selectionBar.addArrangedSubview(editFigure)
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

  @objc private func focusEditor() {
    onFocusRequested()
    becomeFirstResponder()
  }

  private var keyboardEditingAllowed: Bool {
    editorKeyboardEditingAllowed(
      active: hostActive,
      focused: hostFocused,
      figureCaptureActive: figureCaptureActive,
      figureCompleting: figureCompleting)
  }

  @objc private func keyboardCopy() {
    guard keyboardEditingAllowed else { return }
    copySelection()
  }

  @objc private func keyboardCut() {
    guard keyboardEditingAllowed else { return }
    cutSelection()
  }

  @objc private func keyboardDuplicate() {
    guard keyboardEditingAllowed else { return }
    duplicateSelection()
  }

  @objc private func keyboardUngroupSelection() {
    guard keyboardEditingAllowed, canvasView.selectionFrame() != nil else { return }
    ungroupSelection()
  }

  @objc private func keyboardLinkSelection() {
    guard keyboardEditingAllowed, canvasView.selectionPage() != nil else { return }
    linkSelection()
  }

  @objc private func keyboardBookmarkSelection() {
    guard keyboardEditingAllowed, canvasView.selectionFrame() != nil else { return }
    bookmarkSelection()
  }

  @objc private func keyboardSaveClipping() {
    guard keyboardEditingAllowed, canvasView.selectionFrame() != nil else { return }
    saveClipping()
  }

  @objc private func keyboardClippings() {
    guard keyboardEditingAllowed else { return }
    onShowClippingsRequested()
  }

  @objc private func keyboardInsertImage() {
    guard keyboardEditingAllowed else { return }
    onInsertImageRequested()
  }

  private func keyboardZoom(by factor: CGFloat) {
    guard hostActive, hostFocused, scrollView.bounds.width > 0, scrollView.bounds.height > 0 else { return }
    let scale = min(max(scrollView.zoomScale * factor, scrollView.minimumZoomScale),
                    scrollView.maximumZoomScale)
    guard abs(scale - scrollView.zoomScale) > 0.001 else { return }
    let center = CGPoint(x: scrollView.contentOffset.x + scrollView.bounds.width / 2,
                         y: scrollView.contentOffset.y + scrollView.bounds.height / 2)
    let size = CGSize(width: scrollView.bounds.width / scale,
                      height: scrollView.bounds.height / scale)
    scrollView.zoom(to: CGRect(x: center.x / scrollView.zoomScale - size.width / 2,
                               y: center.y / scrollView.zoomScale - size.height / 2,
                               width: size.width, height: size.height), animated: true)
  }

  @objc private func keyboardZoomIn() { keyboardZoom(by: 1.25) }

  @objc private func keyboardZoomOut() { keyboardZoom(by: 0.8) }

  @objc private func keyboardFitPages() {
    guard hostActive, hostFocused else { return }
    fitPages(animated: true, preserveLeadingPosition: true)
  }

  private func keyboardNavigatePage(by offset: Int) {
    guard hostActive, hostFocused, let count = try? document.pageCount(), count > 0 else { return }
    let center = CGPoint(x: canvasView.bounds.midX, y: canvasView.bounds.midY)
    let current = canvasView.page(at: center) ?? max(0, reportedPage)
    let target = min(max(current + offset, 0), count - 1)
    guard target != current else { return }
    scrollToPage(target)
  }

  @objc private func keyboardPreviousPage() {
    keyboardNavigatePage(by: -1)
  }

  @objc private func keyboardNextPage() {
    keyboardNavigatePage(by: 1)
  }

  @objc private func keyboardPreviousHorizontalPage() {
    guard appliedArrangement == .horizontal else { return }
    keyboardNavigatePage(by: -1)
  }

  @objc private func keyboardNextHorizontalPage() {
    guard appliedArrangement == .horizontal else { return }
    keyboardNavigatePage(by: 1)
  }

  private func keyboardNavigateToEdge(last: Bool) {
    guard hostActive, hostFocused, let count = try? document.pageCount(), count > 0 else { return }
    scrollToPage(last ? count - 1 : 0)
  }

  @objc private func keyboardFirstPage() {
    keyboardNavigateToEdge(last: false)
  }

  @objc private func keyboardLastPage() {
    keyboardNavigateToEdge(last: true)
  }

  @objc private func keyboardSave() {
    guard hostActive, hostFocused else { return }
    guard !figureCaptureActive, !figureCompleting else {
      onError(
        EngineDocumentError.operation(
          "Save notebook",
          "Complete the drawing before saving."))
      return
    }
    onSaveRequested()
  }

  @objc private func keyboardUndo() {
    guard keyboardEditingAllowed else { return }
    onUndo()
  }

  @objc private func keyboardRedo() {
    guard keyboardEditingAllowed else { return }
    onRedo()
  }

  @objc private func keyboardSelectAll() {
    guard keyboardEditingAllowed else { return }
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
    guard keyboardEditingAllowed else { return }
    pasteFromPasteboard(at: CGPoint(x: canvasView.bounds.midX, y: canvasView.bounds.midY))
  }

  @objc private func keyboardDelete() {
    guard keyboardEditingAllowed, canvasView.selectionFrame() != nil else { return }
    deleteSelection()
  }

  @objc private func keyboardEscape() {
    guard hostActive, hostFocused, !figureCompleting else { return }
    if figureCaptureActive {
      do {
        try canvasView.cancelFigure()
        figureCaptureActive = false
        figurePreviewGeneration &+= 1
        onFigureSourceChanged("")
        onFigureCaptureChanged(false)
        updateSaveClippingVisibility()
        syncDrawingSuppression()
        refreshSelectionBar()
      } catch {
        onError(error)
      }
    } else if bookmarkMode {
      bookmarkMode = false
      onBookmarkModeChanged(false)
      syncDrawingSuppression()
    } else {
      clearSelection()
    }
  }

  @objc private func clearSelection() {
    guard keyboardEditingAllowed, canvasView.selectionFrame() != nil else { return }
    do {
      try canvasView.clearSelection()
      refreshSelectionBar()
    } catch {
      onError(error)
    }
  }

  private func canvasInteractionBegan() {
    onFocusRequested()
    becomeFirstResponder()
    lastAlignmentStep = nil
    canvasFeedback?.prepare()
  }

  private func canvasInteractionChanged(at point: CGPoint) {
    do {
      guard let step = try canvasView.alignmentStep() else {
        lastAlignmentStep = nil
        return
      }
      if alignmentFeedbackNeeded(previous: lastAlignmentStep, current: step) {
        canvasFeedback?.alignmentOccurred(at: point)
        lastAlignmentStep = step
      }
    } catch {
      lastAlignmentStep = nil
      onError(error)
    }
  }

  private func canvasInteractionEnded() {
    lastAlignmentStep = nil
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
    editFigureButton?.isHidden = selectedFigure == nil || figureCaptureActive || figureCompleting
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
    let safe = view.safeAreaLayoutGuide.layoutFrame
    let size = selectionBar.sizeThatFits(
      CGSize(width: max(44, safe.width - 16), height: .greatestFiniteMagnitude))
    let minimumX = safe.minX + 8
    let maximumX = max(minimumX, safe.maxX - size.width - 8)
    let x = min(max(target.midX - size.width / 2, minimumX), maximumX)
    let preferredY = target.maxY + size.height + 8 <= safe.maxY
      ? target.maxY + 8
      : target.minY - size.height - 8
    let minimumY = safe.minY + 8
    let maximumY = max(minimumY, safe.maxY - size.height - 8)
    let y = min(max(preferredY, minimumY), maximumY)
    selectionBar.frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
  }

  private func reportSelection(_ active: Bool) {
    guard active != reportedSelectionActive else { return }
    reportedSelectionActive = active
    onSelectionChanged(active)
  }

  private func writeSelectionToPasteboard(_ svg: String) {
    UIPasteboard.general.items = [[
      UTType.svg.identifier: Data(svg.utf8),
      UTType.utf8PlainText.identifier: svg,
    ]]
  }

  private func selectionFromPasteboard() -> String? {
    if let data = UIPasteboard.general.data(forPasteboardType: UTType.svg.identifier),
      let svg = String(data: data, encoding: .utf8) {
      return svg
    }
    return UIPasteboard.general.string
  }

  private func pasteFromPasteboard(at point: CGPoint, placeAtPointer: Bool = false) {
    if let svg = selectionFromPasteboard(), svg.contains("<svg") {
      paste(svg, at: point, placeAtPointer: placeAtPointer)
      return
    }
    let pasteboard = UIPasteboard.general
    let imageType: UTType
    if pasteboard.data(forPasteboardType: UTType.png.identifier) != nil {
      imageType = .png
    } else if pasteboard.data(forPasteboardType: UTType.jpeg.identifier) != nil {
      imageType = .jpeg
    } else if let rasterType = [UTType.heic, .heif, .tiff].first(where: {
      pasteboard.data(forPasteboardType: $0.identifier) != nil
    }) {
      imageType = rasterType
    } else if pasteboard.image != nil {
      imageType = .png
    } else {
      return
    }
    let data = pasteboard.data(forPasteboardType: imageType.identifier)
      ?? (imageType == .png ? pasteboard.image?.pngData() : nil)
    guard let data,
      let image = UIImage(data: data)?.cgImage,
      let page = canvasView.page(at: point)
    else { return }
    do {
      let bounds = try document.pageRect(index: page)
      let importedData: Data
      let mimeType: String
      switch imageType {
      case .png:
        importedData = data
        mimeType = "image/png"
      case .jpeg:
        importedData = data
        mimeType = "image/jpeg"
      default:
        guard let png = UIImage(cgImage: image).pngData() else { return }
        importedData = png
        mimeType = "image/png"
      }
      let svg = try imageImportSVG(
        data: importedData, mimeType: mimeType,
        imageSize: CGSize(width: image.width, height: image.height),
        pageSize: bounds.size)
      paste(svg, at: point, placeAtPointer: placeAtPointer)
    } catch {
      onError(error)
    }
  }

  @objc private func copySelection() {
    do {
      guard let svg = try canvasView.copySelection(), !svg.isEmpty else { return }
      writeSelectionToPasteboard(svg)
    } catch {
      onError(error)
    }
  }

  @objc private func cutSelection() {
    do {
      guard let svg = try canvasView.cutSelection(), !svg.isEmpty else { return }
      writeSelectionToPasteboard(svg)
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
      guard let svg = try canvasView.copySelection(), !svg.isEmpty else { return }
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
    var succeeded = false
    defer { onPageCommandHandled(command, succeeded) }
    do {
      switch command.action {
      case .identified:
        break
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
        if let svg = try canvasView.copySelection(), !svg.isEmpty {
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
      succeeded = true
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
          guard self.figureCaptureActive, !self.figureCompleting,
            generation == self.figurePreviewGeneration else { return }
          self.onFigureSourceChanged(generated.source)
        } catch {
          guard self.figureCaptureActive, !self.figureCompleting,
            generation == self.figurePreviewGeneration else { return }
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
        refreshSelectionBar()
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
      canvasFeedback?.prepare()
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
          self.refreshSelectionBar()
          if !id.isEmpty {
            self.canvasFeedback?.pathCompleted(at: CGPoint(x: self.canvasView.bounds.midX, y: self.canvasView.bounds.midY))
            self.onEditCommitted()
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
    guard recognizer.state == .ended, hostActive, hostFocused else { return }
    onFocusRequested()
    let point = recognizer.location(in: canvasView)
    guard !figureCaptureActive, !figureCompleting else { return }
    guard !handleModeTap(at: point) else { return }
    guard appliedTool == .navigate else { return }
    followLink(at: point)
  }

  @objc private func handlePencilModeTap(_ recognizer: UITapGestureRecognizer) {
    guard recognizer.state == .ended, hostActive, hostFocused else { return }
    onFocusRequested()
    let point = recognizer.location(in: canvasView)
    guard !figureCaptureActive, !figureCompleting else { return }
    if handleModeTap(at: point) { return }
    guard appliedTool == .navigate else { return }
    followLink(at: point)
  }

  @objc private func handleUndoTap(_ recognizer: UITapGestureRecognizer) {
    guard recognizer.state == .ended, keyboardEditingAllowed else { return }
    onFocusRequested()
    onUndo()
  }

  @objc private func handleRedoTap(_ recognizer: UITapGestureRecognizer) {
    guard recognizer.state == .ended, keyboardEditingAllowed else { return }
    onFocusRequested()
    onRedo()
  }

  @objc private func handlePencilHover(_ recognizer: UIHoverGestureRecognizer) {
    guard hostActive, hostFocused, !pencilStrokeActive else {
      pencilHoverIndicator.isHidden = true
      return
    }

    switch recognizer.state {
    case .began, .changed:
      canvasView.sendPencilHover(
        location: recognizer.location(in: canvasView),
        altitude: recognizer.altitudeAngle,
        azimuth: recognizer.azimuthAngle(in: canvasView),
        roll: recognizer.rollAngle,
        hoverHeight: recognizer.zOffset)
      guard pencilHoverPreviewAllowed(
        preference: UIPencilInteraction.prefersHoverToolPreview,
        hostActive: hostActive,
        hostFocused: hostFocused,
        pencilStrokeActive: pencilStrokeActive)
      else {
        pencilHoverIndicator.isHidden = true
        return
      }
      let settings: InkToolSettings
      switch appliedTool {
      case .pen:
        settings = appliedPens.pen
      case .marker:
        settings = appliedPens.marker
      case .highlighter:
        settings = appliedPens.highlighter
      default:
        pencilHoverIndicator.isHidden = true
        return
      }

      let rgb = settings.rgb
      let color = UIColor(
        red: CGFloat((rgb >> 16) & 0xFF) / 255,
        green: CGFloat((rgb >> 8) & 0xFF) / 255,
        blue: CGFloat(rgb & 0xFF) / 255,
        alpha: 1)
      let base = min(max(CGFloat(settings.size) * scrollView.zoomScale, 6), 48)
      let altitude = max(recognizer.altitudeAngle, 0.15)
      let major = min(max(base / max(sin(altitude), 0.25), base), 48)
      let location = recognizer.location(in: view)

      pencilHoverIndicator.transform = .identity
      pencilHoverIndicator.bounds = CGRect(x: 0, y: 0, width: major, height: base)
      pencilHoverIndicator.center = location
      pencilHoverIndicator.layer.cornerRadius = base / 2
      pencilHoverIndicator.layer.borderColor = color.withAlphaComponent(0.85).cgColor
      pencilHoverIndicator.backgroundColor = color.withAlphaComponent(0.12)
      pencilHoverIndicator.alpha = 1 - 0.7 * min(max(recognizer.zOffset, 0), 1)
      pencilHoverIndicator.transform = CGAffineTransform(
        rotationAngle: recognizer.azimuthAngle(in: view))
      pencilHoverIndicator.isHidden = false
    case .ended, .cancelled, .failed:
      pencilHoverIndicator.isHidden = true
    default:
      break
    }
  }

  func pencilInteraction(
    _ interaction: UIPencilInteraction,
    didReceiveTap tap: UIPencilInteraction.Tap
  ) {
    guard hostActive, hostFocused else { return }
    onFocusRequested()
    onPencilAction(UIPencilInteraction.preferredTapAction, tap.hoverPose?.location)
  }

  func pencilInteraction(
    _ interaction: UIPencilInteraction,
    didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze
  ) {
    guard hostActive, hostFocused, squeeze.phase == .ended else { return }
    onFocusRequested()
    onPencilAction(UIPencilInteraction.preferredSqueezeAction, squeeze.hoverPose?.location)
  }

  @discardableResult
  private func handleModeTap(at point: CGPoint) -> Bool {
    if bookmarkMode {
      guard canvasView.page(at: point) != nil else { return true }
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
      guard canvasView.page(at: point) != nil else { return true }
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

  private func paste(_ svg: String, at point: CGPoint, placeAtPointer: Bool = false) {
    do {
      try canvasView.paste(svg, at: point, placeAtPointer: placeAtPointer)
      onEditCommitted()
      refreshSelectionBar()
    } catch {
      onError(error)
    }
  }

  private func configureBottomPull() {
    addPageFooter.mj_h = 96
    addPageFooter.stateLabel?.textColor = NativeTheme.inkUI
    addPageFooter.stateLabel?.font = UIFont(
      name: NativeTheme.interfaceRegularName, size: 16)
    addPageFooter.setTitle("Pull and hold to add a page", for: .idle)
    addPageFooter.setTitle("Hold to add a page", for: .pulling)
    addPageFooter.setTitle("Adding page…", for: .refreshing)
    scrollView.mj_footer = addPageFooter
  }

  private func trackBottomPull() {
    guard editorDocumentMutationAllowed(
      figureCaptureActive: figureCaptureActive,
      figureCompleting: figureCompleting)
    else {
      releasedPullWasArmed = false
      footerWasPulling = false
      pullGate.leftReady()
      cancelPullReadyTimer()
      return
    }

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
    let shouldAdd =
      releasedPullWasArmed &&
      editorDocumentMutationAllowed(
        figureCaptureActive: figureCaptureActive,
        figureCompleting: figureCompleting)
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

  private func reportFitState() {
    guard let fit = fitScale(), fit > 0 else { return }
    let fitted = abs(scrollView.zoomScale / fit - 1) <= 0.001
    guard fitted != reportedFitActive else { return }
    reportedFitActive = fitted
    DispatchQueue.main.async { [onFitStateChanged] in
      onFitStateChanged(fitted)
    }
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
final class SelectionActionWrapView: UIView {
  private let spacing: CGFloat
  private let contentInset: CGFloat
  private var actionSubviews: [UIView] = []

  init(spacing: CGFloat, contentInset: CGFloat) {
    self.spacing = spacing
    self.contentInset = contentInset
    super.init(frame: .zero)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  func addArrangedSubview(_ view: UIView) {
    actionSubviews.append(view)
    addSubview(view)
  }

  override func sizeThatFits(_ size: CGSize) -> CGSize {
    let available = max(44, size.width - 2 * contentInset)
    let measured = measure(maxWidth: available)
    return CGSize(
      width: measured.width + 2 * contentInset,
      height: measured.height + 2 * contentInset)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let available = max(44, bounds.width - 2 * contentInset)
    var x = contentInset
    var y = contentInset
    var rowHeight: CGFloat = 0

    for view in actionSubviews where !view.isHidden {
      let item = view.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
      if x > contentInset, x + item.width > contentInset + available {
        x = contentInset
        y += rowHeight + spacing
        rowHeight = 0
      }
      view.frame = CGRect(origin: CGPoint(x: x, y: y), size: item)
      x += item.width + spacing
      rowHeight = max(rowHeight, item.height)
    }
  }

  private func measure(maxWidth: CGFloat) -> CGSize {
    var x: CGFloat = 0
    var y: CGFloat = 0
    var rowHeight: CGFloat = 0
    var usedWidth: CGFloat = 0

    for view in actionSubviews where !view.isHidden {
      let item = view.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
      if x > 0, x + item.width > maxWidth {
        x = 0
        y += rowHeight + spacing
        rowHeight = 0
      }
      usedWidth = max(usedWidth, x + item.width)
      x += item.width + spacing
      rowHeight = max(rowHeight, item.height)
    }
    return CGSize(width: min(usedWidth, maxWidth), height: y + rowHeight)
  }
}

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
  let fingerDraws: Bool
  let clippingsOpen: Bool
  let onFocus: () -> Void
  let onViewportChanged: (EditorLinkedViewport) -> Void
  let onFitStateChanged: (Bool) -> Void
  let onEditCommitted: () -> Void
  let onSaveRequested: () -> Void
  let onInsertImageRequested: () -> Void
  let onShowClippingsRequested: () -> Void
  let onCurrentPageChanged: (Int) -> Void
  let onPageCommandHandled: (EditorPageCommand, Bool) -> Void
  let onBookmarkModeChanged: (Bool) -> Void
  let onTextRequested: (EditorTextRequest) -> Void
  let onLinkSelectionRequested: (Int) -> Void
  let onFollowLink: (String, Int) -> Void
  let onSaveClipping: (String) -> Void
  let onSelectionChanged: (Bool) -> Void
  let onUndo: () -> Void
  let onRedo: () -> Void
  let onPencilAction: (UIPencilPreferredAction, CGPoint?) -> Void
  let onFigureCaptureChanged: (Bool) -> Void
  let onFigureSourceChanged: (String) -> Void
  let onEditFigure: (String) -> Void
  let onError: (Error) -> Void

  func makeUIViewController(context: Context) -> InkEditorViewController {
    InkEditorViewController(
      document: document,
      onFocusRequested: onFocus,
      onViewportChanged: onViewportChanged,
      onFitStateChanged: onFitStateChanged,
      onEditCommitted: onEditCommitted,
      onSaveRequested: onSaveRequested,
      onInsertImageRequested: onInsertImageRequested,
      onShowClippingsRequested: onShowClippingsRequested,
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

func modeBannerAccessibilityLabel(mode: String, showsBookmarkHint: Bool) -> String {
  showsBookmarkHint ? "\(mode)\nTap the line to mark." : mode
}

func editorPageCounterText(currentPage: Int, pageCount: Int) -> String {
  let total = max(1, pageCount)
  let page = min(max(currentPage, 0), total - 1)
  return "\(page + 1) / \(total)"
}

func editorToolForDrawingEntry(
  tool: EditorTool,
  drawingTool: EditorTool
) -> EditorTool {
  [EditorTool.pen, .marker, .highlighter].contains(tool) ? tool : drawingTool
}

@MainActor
struct InkEditorView: View {
  let document: EngineDocument
  let arrangement: EditorPageArrangement
  let fitRevision: Int
  @Binding var penLibrary: EditorPenLibrary
  @Binding var tool: EditorTool
  @Binding var drawingTool: EditorTool
  @Binding var eraserMode: EditorEraserMode
  @Binding var selectorMode: EditorSelectorMode
  @Binding var spaceMode: EditorSpaceMode
  @Binding var previousPencilTool: EditorTool?
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
  @State private var textRequest: EditorTextRequest?
  @State private var drawing = false
  @State private var figureSource = ""
  @State private var selectionActive = false
  @State private var pencilPaletteAnchor: CGPoint?
  let onFocus: () -> Void
  let onViewportChanged: (EditorLinkedViewport) -> Void
  let onFitStateChanged: (Bool) -> Void
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
        fingerDraws: fingerDraws,
        clippingsOpen: clippingsOpen,
        onFocus: onFocus,
        onViewportChanged: onViewportChanged,
        onFitStateChanged: onFitStateChanged,
        onEditCommitted: {
          documentRevision &+= 1
          onEditCommitted()
        },
        onSaveRequested: onSaveRequested,
        onInsertImageRequested: onInsertImage,
        onShowClippingsRequested: onShowClippings,
        onCurrentPageChanged: { currentPage = $0 },
        onPageCommandHandled: { handled, _ in
          DispatchQueue.main.async {
            if pageCommand == handled { pageCommand = nil }
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
        insertText: { pageCommand = .identified(UUID(), .requestTextAtCenter) },
        insertImage: onInsertImage,
        drawing: drawing,
        selectionActive: selectionActive,
        clippingsOpen: clippingsOpen,
        toggleDrawing: toggleDrawingMode,
        showClippings: onShowClippings,
        recolorSelection: { rgb in pageCommand = .identified(UUID(), .recolorSelection(rgb)) },
        onPensChanged: onPensChanged)

      if let pencilPaletteAnchor {
        Color.clear
          .frame(width: 1, height: 1)
          .position(pencilPaletteAnchor)
          .popover(
            isPresented: Binding(
              get: { self.pencilPaletteAnchor != nil },
              set: { if !$0 { self.pencilPaletteAnchor = nil } }),
            arrowEdge: .top
          ) {
            ColorPalettePopover(
              tool: $tool,
              drawingTool: $drawingTool,
              library: $penLibrary,
              selectionActive: selectionActive,
              onRecolorSelection: { rgb in pageCommand = .identified(UUID(), .recolorSelection(rgb)) },
              onPersist: onPensChanged)
              .presentationCompactAdaptation(.popover)
          }
      }

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
          HStack(spacing: 10) {
            Text(mode)
              .font(NativeTheme.subhead)
            if bookmarkMode && !drawing {
              Text("Tap the line to mark.")
                .font(NativeTheme.callout)
                .foregroundStyle(NativeTheme.graphite)
            }
          }
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(modeBannerAccessibilityLabel(mode: mode, showsBookmarkHint: bookmarkMode && !drawing))
          if drawing {
            Button("Complete") {
              toggleDrawingMode()
            }
            .frame(minWidth: 36, minHeight: 36)
          } else {
            Button {
              closeModeBanner()
            } label: {
              Image(systemName: "xmark")
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
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
      of: [notebookClippingDragType],
      delegate: NotebookEditorDropDelegate(
        canDrop: { !drawing },
        onFocus: onFocus,
        onDropClipping: onDropClipping))
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
          pageCommand = .identified(UUID(), .commitText(request, properties))
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
    if !drawing {
      bookmarkMode = false
      tool = editorToolForDrawingEntry(tool: tool, drawingTool: drawingTool)
    }
    pageCommand = .identified(UUID(), .toggleFigureCapture(currentPage))
  }

  private func closeModeBanner() {
    if bookmarkMode {
      bookmarkMode = false
    } else {
      tool = drawingTool
    }
  }

  private func applyPencilAction(_ action: UIPencilPreferredAction, at point: CGPoint?) {
    let result = applyPreferredPencilAction(
      action, tool: tool, previousTool: previousPencilTool, point: point)
    tool = result.tool
    previousPencilTool = result.previousTool
    if let paletteAnchor = result.paletteAnchor {
      pencilPaletteAnchor = paletteAnchor
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
      let normalizedLayerID = editableActiveLayerID(layers: layers, current: activeLayerID)
      if normalizedLayerID != activeLayerID {
        activeLayerID = normalizedLayerID
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
      let normalizedLayerID = editableActiveLayerID(layers: layers, current: activeLayerID)
      if normalizedLayerID != activeLayerID {
        activeLayerID = normalizedLayerID
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
