import Foundation
import InkEngine
import Metal
import QuartzCore
import UIKit

@MainActor
final class InkCanvasView: UIView {
  override class var layerClass: AnyClass { CAMetalLayer.self }

  private let device: any MTLDevice
  private let queue: any MTLCommandQueue
  private var canvas: OpaquePointer?
  private var updateLink: UIUpdateLink?
  private var sampleIDs = PencilSampleIDs()
  private let onInteractionEnded: () -> Void

  private var metalLayer: CAMetalLayer {
    layer as! CAMetalLayer
  }

  init(document: EngineDocument, onInteractionEnded: @escaping () -> Void = {}) {
    guard let device = MTLCreateSystemDefaultDevice(),
          let queue = device.makeCommandQueue()
    else {
      fatalError("Metal is unavailable")
    }
    self.device = device
    self.queue = queue
    self.onInteractionEnded = onInteractionEnded

    super.init(frame: .zero)

    isOpaque = true
    isMultipleTouchEnabled = true
    backgroundColor = .clear

    metalLayer.device = device
    metalLayer.pixelFormat = .bgra8Unorm
    metalLayer.framebufferOnly = true

    var engineCanvas: OpaquePointer?
    let createStatus = ink_canvas_create_metal(
      document.pointer,
      Unmanaged.passUnretained(device).toOpaque(),
      Unmanaged.passUnretained(queue).toOpaque(),
      Unmanaged.passUnretained(metalLayer).toOpaque(),
      &engineCanvas)
    guard createStatus == INK_OK, let engineCanvas else {
      fatalError("ink_canvas_create_metal failed: \(EngineDocument.lastError())")
    }
    canvas = engineCanvas

    applyTool(.pen, pens: .defaults)

    let link = UIUpdateLink(view: self) { [weak self] _, _ in
      self?.render()
    }
    link.requiresContinuousUpdates = true
    link.wantsLowLatencyEventDispatch = true
    link.wantsImmediatePresentation = true
    link.isEnabled = true
    updateLink = link
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  deinit {
    updateLink?.isEnabled = false
    if let canvas {
      ink_canvas_free(canvas)
    }
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    updateSurfaceSize()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    metalLayer.frame = bounds
    updateSurfaceSize()
  }

  func applyTool(_ tool: EditorTool, pens: EditorPenSet, eraserMode: EditorEraserMode = .stroke, selectorMode: EditorSelectorMode = .freehand) {
    guard let canvas else { return }

    func setEraser(active: Bool) {
      check(
        ink_canvas_set_eraser(canvas, eraserMode.engineValue, active ? 1 : 0),
        operation: "ink_canvas_set_eraser")
    }

    func setSelector(_ kind: InkSelector, active: Bool) {
      check(
        ink_canvas_set_selector(canvas, kind, active ? 1 : 0),
        operation: "ink_canvas_set_selector")
    }

    switch tool {
    case .eraser:
      if let selector = eraserMode.selectorValue {
        setSelector(selector, active: true)
      } else {
        setEraser(active: true)
      }
    case .lasso:
      setSelector(selectorMode.engineValue, active: true)
    case .pen, .marker, .highlighter:
      setEraser(active: false)
      setSelector(selectorMode.engineValue, active: false)
      var settings = switch tool {
      case .pen: pens.pen
      case .marker: pens.marker
      case .highlighter: pens.highlighter
      case .eraser, .lasso: pens.pen
      }
      check(ink_canvas_set_tool(canvas, &settings), operation: "ink_canvas_set_tool")
    }
  }

  func setViewTransform(_ transform: CGAffineTransform) {
    guard let canvas else { return }
    check(
      ink_canvas_set_view(
        canvas,
        transform.a, transform.b, transform.c, transform.d,
        transform.tx, transform.ty),
      operation: "ink_canvas_set_view")
  }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    sendPencilTouches(touches, event: event)
  }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    sendPencilTouches(touches, event: event)
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    let handled = sendPencilTouches(touches, event: event)
    if handled {
      onInteractionEnded()
    }
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
    sendPencilTouches(touches, event: event)
  }

  override func touchesEstimatedPropertiesUpdated(_ touches: Set<UITouch>) {
    guard let canvas else { return }

    var updates: [InkPenSample] = []
    for touch in touches where touch.type == .pencil {
      guard let id = sampleIDs.updateID(estimationIndex: touch.estimationUpdateIndex) else {
        continue
      }
      updates.append(
        PencilSampleFactory.make(
          values: PencilSampleFactory.values(for: touch, in: self),
          id: id,
          predicted: false))
      if touch.estimatedPropertiesExpectingUpdates.isEmpty {
        sampleIDs.finish(estimationIndex: touch.estimationUpdateIndex)
      }
    }

    guard !updates.isEmpty else { return }
    let status = updates.withUnsafeBufferPointer { buffer in
      ink_input_update(canvas, buffer.baseAddress, buffer.count)
    }
    check(status, operation: "ink_input_update")
  }

  @discardableResult
  private func sendPencilTouches(_ touches: Set<UITouch>, event: UIEvent?) -> Bool {
    guard let canvas else { return false }

    var samples: [InkPenSample] = []
    for touch in touches where touch.type == .pencil {
      let coalesced = event?.coalescedTouches(for: touch) ?? [touch]
      for realTouch in coalesced {
        let trackEstimate =
          realTouch.estimationUpdateIndex != nil &&
          !realTouch.estimatedPropertiesExpectingUpdates.isEmpty
        let id = sampleIDs.issue(
          estimationIndex: realTouch.estimationUpdateIndex,
          trackEstimate: trackEstimate)
        samples.append(
          PencilSampleFactory.make(
            values: PencilSampleFactory.values(for: realTouch, in: self),
            id: id,
            predicted: false))
      }

      if touch.phase != .ended && touch.phase != .cancelled {
        for predictedTouch in event?.predictedTouches(for: touch) ?? [] {
          let id = sampleIDs.issue(estimationIndex: nil, trackEstimate: false)
          samples.append(
            PencilSampleFactory.make(
              values: PencilSampleFactory.values(for: predictedTouch, in: self),
              id: id,
              predicted: true))
        }
      }
    }

    guard !samples.isEmpty else { return false }
    let status = samples.withUnsafeBufferPointer { buffer in
      ink_input(canvas, buffer.baseAddress, buffer.count)
    }
    check(status, operation: "ink_input")
    return status == INK_OK && touches.contains {
      $0.type == .pencil && $0.phase == .ended
    }
  }

  func page(at point: CGPoint) -> Int? {
    guard let canvas else { return nil }
    var page: Int32 = -1
    let status = ink_canvas_page_at(canvas, point.x, point.y, &page)
    check(status, operation: "ink_canvas_page_at")
    guard status == INK_OK, page >= 0 else { return nil }
    return Int(page)
  }

  func selectionFrame() -> CGRect? {
    guard let canvas else { return nil }
    var info = InkSelectionInfo()
    let status = ink_canvas_selection(canvas, &info)
    check(status, operation: "ink_canvas_selection")
    guard status == INK_OK, info.count > 0 else { return nil }
    return CGRect(x: info.x, y: info.y, width: info.width, height: info.height)
  }

  func selectAll(page: Int) throws {
    guard let canvas else { return }
    try require(ink_canvas_select_all(canvas, page), operation: "Select page")
  }

  func activeLayer() throws -> Int {
    guard let canvas else { return -1 }
    var index: Int32 = -1
    try require(ink_canvas_active_layer(canvas, &index), operation: "Read active layer")
    return Int(index)
  }

  func setLayer(_ index: Int) throws {
    guard let canvas else { return }
    try require(ink_canvas_set_layer(canvas, index), operation: "Set active layer")
  }

  func copySelection() throws -> String? {
    guard let canvas else { return nil }
    var bytes: UnsafePointer<UInt8>?
    var size = 0
    try require(
      ink_canvas_copy_selection(canvas, 0, &bytes, &size),
      operation: "Copy selection")
    guard size > 0, let bytes else { return nil }
    return String(decoding: UnsafeBufferPointer(start: bytes, count: size), as: UTF8.self)
  }

  func deleteSelection() throws {
    guard let canvas else { return }
    try require(ink_canvas_delete_selection(canvas), operation: "Delete selection")
  }

  func duplicateSelection() throws {
    guard let canvas else { return }
    try require(ink_canvas_duplicate_selection(canvas), operation: "Duplicate selection")
  }

  func paste(_ svg: String, at point: CGPoint) throws {
    guard let canvas else { return }
    let data = Data(svg.utf8)
    let status = data.withUnsafeBytes { raw in
      ink_canvas_paste(
        canvas,
        raw.baseAddress?.assumingMemoryBound(to: UInt8.self),
        raw.count,
        point.x,
        point.y)
    }
    try require(status, operation: "Paste selection")
  }

  private func require(_ status: InkStatus, operation: String) throws {
    guard status != INK_OK else { return }
    throw EngineDocumentError.operation(operation, EngineDocument.lastError())
  }

  private func updateSurfaceSize() {
    guard let canvas else { return }
    let scale = window?.screen.scale ?? UIScreen.main.scale
    metalLayer.contentsScale = scale
    let width = Int32(ceil(bounds.width * scale))
    let height = Int32(ceil(bounds.height * scale))
    guard width > 0, height > 0 else { return }
    check(
      ink_canvas_set_surface_size(canvas, width, height, Float(scale)),
      operation: "ink_canvas_set_surface_size")
  }

  private func render() {
    guard let canvas else { return }
    var drew: Int32 = 0
    check(ink_render(canvas, &drew), operation: "ink_render")
  }

  private func check(_ status: InkStatus, operation: String) {
    guard status != INK_OK else { return }
    assertionFailure("\(operation) failed: \(EngineDocument.lastError())")
  }
}
