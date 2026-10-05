import Foundation
import InkEngine
import Metal
import QuartzCore
import UIKit

struct EngineTextProperties: Codable, Equatable {
  var content: String
  var width: Double
  var rtl: Bool
}

@MainActor
final class InkCanvasView: UIView {
  override class var layerClass: AnyClass { CAMetalLayer.self }

  private let device: any MTLDevice
  private let queue: any MTLCommandQueue
  private var canvas: OpaquePointer?
  private var updateLink: UIUpdateLink?
  private var sampleIDs = PencilSampleIDs()
  private var drawingSuppressed = false
  private var fingerDrawing = false
  private var fingerTouch: UITouch?
  private let onInteractionBegan: () -> Void
  private let onInteractionEnded: () -> Void
  private let onPencilStrokeChanged: (Bool) -> Void

  private var metalLayer: CAMetalLayer {
    layer as! CAMetalLayer
  }

  init(
    document: EngineDocument,
    onInteractionBegan: @escaping () -> Void = {},
    onInteractionEnded: @escaping () -> Void = {},
    onPencilStrokeChanged: @escaping (Bool) -> Void = { _ in }
  ) {
    guard let device = MTLCreateSystemDefaultDevice(),
          let queue = device.makeCommandQueue()
    else {
      fatalError("Metal is unavailable")
    }
    self.device = device
    self.queue = queue
    self.onInteractionBegan = onInteractionBegan
    self.onInteractionEnded = onInteractionEnded
    self.onPencilStrokeChanged = onPencilStrokeChanged

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

  func applyTool(
    _ tool: EditorTool,
    pens: EditorPenSet,
    eraserMode: EditorEraserMode = .stroke,
    selectorMode: EditorSelectorMode = .freehand,
    spaceMode: EditorSpaceMode = .reflow
  ) {
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
    case .space:
      setSelector(spaceMode.engineValue, active: true)
    case .text, .navigate:
      setEraser(active: false)
      setSelector(selectorMode.engineValue, active: false)
    case .image:
      setEraser(active: false)
      setSelector(selectorMode.engineValue, active: false)
    case .pen, .marker, .highlighter:
      setEraser(active: false)
      setSelector(selectorMode.engineValue, active: false)
      var settings = switch tool {
      case .pen: pens.pen
      case .marker: pens.marker
      case .highlighter: pens.highlighter
      case .eraser, .lasso, .space, .text, .image, .navigate: pens.pen
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

  func setActive(_ active: Bool) {
    updateLink?.isEnabled = active
  }

  func setDrawingSuppressed(_ suppressed: Bool) {
    drawingSuppressed = suppressed
    if suppressed {
      cancelFingerStroke()
    }
  }

  func setFingerDrawing(_ enabled: Bool) {
    guard fingerDrawing != enabled else { return }
    if !enabled {
      cancelFingerStroke()
    }
    fingerDrawing = enabled
  }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    if touches.contains(where: { $0.type == .pencil }) {
      onPencilStrokeChanged(true)
    }
    onInteractionBegan()
    _ = sendFingerTouches(touches, event: event)
    sendPencilTouches(touches, event: event)
  }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    _ = sendFingerTouches(touches, event: event)
    sendPencilTouches(touches, event: event)
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    let fingerHandled = sendFingerTouches(touches, event: event)
    let pencilHandled = sendPencilTouches(touches, event: event)
    if touches.contains(where: { $0.type == .pencil }) {
      onPencilStrokeChanged(false)
    }
    if fingerHandled || pencilHandled {
      onInteractionEnded()
    }
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
    _ = sendFingerTouches(touches, event: event)
    sendPencilTouches(touches, event: event)
    if touches.contains(where: { $0.type == .pencil }) {
      onPencilStrokeChanged(false)
    }
  }

  override func touchesEstimatedPropertiesUpdated(_ touches: Set<UITouch>) {
    guard !drawingSuppressed, let canvas else { return }

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
  private func sendFingerTouches(_ touches: Set<UITouch>, event: UIEvent?) -> Bool {
    guard fingerDrawing, !drawingSuppressed, let canvas else { return false }

    let activeTouches = event?.touches(for: self) ?? touches
    let pencilActive = activeTouches.contains {
      $0.type == .pencil && $0.phase != .ended && $0.phase != .cancelled
    }
    let activeDirectTouches = activeTouches.filter {
      $0.type == .direct && $0.phase != .ended && $0.phase != .cancelled
    }
    if pencilActive || activeDirectTouches.count >= 2 {
      cancelFingerStroke()
      return false
    }

    if fingerTouch == nil,
      let began = touches.first(where: { $0.type == .direct && $0.phase == .began })
    {
      fingerTouch = began
    }
    guard let fingerTouch, touches.contains(where: { $0 === fingerTouch }) else {
      return false
    }

    let coalesced = event?.coalescedTouches(for: fingerTouch) ?? [fingerTouch]
    var samples: [InkPenSample] = []
    for touch in coalesced {
      let id = sampleIDs.issue(estimationIndex: nil, trackEstimate: false)
      samples.append(
        PencilSampleFactory.make(
          values: PencilSampleFactory.fingerValues(for: touch, in: self),
          id: id,
          predicted: false))
    }
    guard !samples.isEmpty else { return false }
    let status = samples.withUnsafeBufferPointer { buffer in
      ink_input(canvas, buffer.baseAddress, buffer.count)
    }
    check(status, operation: "ink_input")

    let ended = fingerTouch.phase == .ended || fingerTouch.phase == .cancelled
    if ended {
      self.fingerTouch = nil
    }
    return status == INK_OK && ended
  }

  private func cancelFingerStroke() {
    guard let fingerTouch, let canvas else {
      self.fingerTouch = nil
      return
    }
    var values = PencilSampleFactory.fingerValues(for: fingerTouch, in: self)
    values.phase = UInt8(INK_PHASE_CANCEL.rawValue)
    let id = sampleIDs.issue(estimationIndex: nil, trackEstimate: false)
    var sample = PencilSampleFactory.make(values: values, id: id, predicted: false)
    check(ink_input(canvas, &sample, 1), operation: "ink_input")
    self.fingerTouch = nil
  }

  @discardableResult
  private func sendPencilTouches(_ touches: Set<UITouch>, event: UIEvent?) -> Bool {
    guard !drawingSuppressed, let canvas else { return false }

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
    guard let info = selectionInfo() else { return nil }
    return CGRect(x: info.x, y: info.y, width: info.width, height: info.height)
  }

  func selectionPage() -> Int? {
    guard let info = selectionInfo(), info.page >= 0 else { return nil }
    return Int(info.page)
  }

  private func selectionInfo() -> InkSelectionInfo? {
    guard let canvas else { return nil }
    var info = InkSelectionInfo()
    let status = ink_canvas_selection(canvas, &info)
    check(status, operation: "ink_canvas_selection")
    guard status == INK_OK, info.count > 0 else { return nil }
    return info
  }

  func bookmarkSelection() throws {
    guard let canvas else { return }
    try require(ink_canvas_bookmark_selection(canvas), operation: "Bookmark selection")
  }

  func addBookmark(at point: CGPoint) throws {
    guard let canvas else { return }
    try require(
      ink_canvas_add_bookmark(canvas, point.x, point.y),
      operation: "Add bookmark")
  }

  func linkSelection(_ href: String) throws {
    guard let canvas else { return }
    let status = href.withCString { ink_canvas_link_selection(canvas, $0) }
    try require(status, operation: "Link selection")
  }

  func ungroupSelection() throws {
    guard let canvas else { return }
    try require(ink_canvas_ungroup_selection(canvas), operation: "Remove bookmark or link")
  }

  func selectText(at point: CGPoint) throws -> Bool {
    guard let canvas else { return false }
    var found: Int32 = 0
    try require(
      ink_canvas_select_text_at(canvas, point.x, point.y, &found),
      operation: "Select text")
    return found != 0
  }

  func textProperties() throws -> EngineTextProperties {
    guard let canvas else {
      throw EngineDocumentError.operation("Read text properties", "Canvas is unavailable")
    }
    var json: UnsafePointer<CChar>?
    try require(ink_canvas_text_properties(canvas, &json), operation: "Read text properties")
    guard let json else {
      throw EngineDocumentError.operation("Read text properties", "No text properties returned")
    }
    return try JSONDecoder().decode(
      EngineTextProperties.self,
      from: Data(String(cString: json).utf8))
  }

  func editText(
    _ properties: EngineTextProperties,
    at point: CGPoint,
    existing: Bool
  ) throws {
    guard let canvas else { return }
    let data = try JSONEncoder().encode(properties)
    guard let json = String(data: data, encoding: .utf8) else {
      throw EngineDocumentError.operation("Edit text", "Could not encode text properties")
    }
    let status = json.withCString {
      ink_canvas_edit_text(canvas, $0, point.x, point.y, existing ? 1 : 0)
    }
    try require(status, operation: existing ? "Edit text" : "Insert text")
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

  func beginFigure(page: Int) throws {
    guard let canvas else { return }
    let layer = try activeLayer()
    try require(
      ink_canvas_figure_begin(canvas, page, layer),
      operation: "Start drawing mode")
  }

  func figureScene() throws -> String {
    guard let canvas else {
      throw EngineDocumentError.operation("Read figure scene", "Canvas is unavailable")
    }
    var bytes: UnsafePointer<UInt8>?
    var size = 0
    try require(
      ink_canvas_figure_scene(canvas, &bytes, &size),
      operation: "Read figure scene")
    guard let bytes else { return "" }
    return String(decoding: UnsafeBufferPointer(start: bytes, count: size), as: UTF8.self)
  }

  func completeFigure(scene: String, tikz: String) throws -> String {
    guard let canvas else {
      throw EngineDocumentError.operation("Complete figure", "Canvas is unavailable")
    }
    let sceneData = Data(scene.utf8)
    let tikzData = Data(tikz.utf8)
    var idBytes: UnsafePointer<UInt8>?
    var idSize = 0
    let status = sceneData.withUnsafeBytes { sceneRaw in
      tikzData.withUnsafeBytes { tikzRaw in
        ink_canvas_figure_complete(
          canvas,
          sceneRaw.baseAddress?.assumingMemoryBound(to: UInt8.self),
          sceneRaw.count,
          tikzRaw.baseAddress?.assumingMemoryBound(to: UInt8.self),
          tikzRaw.count,
          &idBytes,
          &idSize)
      }
    }
    try require(status, operation: "Complete figure")
    guard idSize > 0, let idBytes else { return "" }
    return String(decoding: UnsafeBufferPointer(start: idBytes, count: idSize), as: UTF8.self)
  }

  func selectedFigure() throws -> String? {
    guard let canvas else { return nil }
    var idBytes: UnsafePointer<UInt8>?
    var size = 0
    try require(
      ink_canvas_selected_figure(canvas, &idBytes, &size),
      operation: "Read selected figure")
    guard size > 0, let idBytes else { return nil }
    return String(decoding: UnsafeBufferPointer(start: idBytes, count: size), as: UTF8.self)
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

  func clearSelection() throws {
    guard let canvas else { return }
    try require(ink_canvas_clear_selection(canvas), operation: "Clear selection")
  }

  func deleteSelection() throws {
    guard let canvas else { return }
    try require(ink_canvas_delete_selection(canvas), operation: "Delete selection")
  }

  func duplicateSelection() throws {
    guard let canvas else { return }
    try require(ink_canvas_duplicate_selection(canvas), operation: "Duplicate selection")
  }

  func recolorSelection(_ rgb: UInt32) throws {
    guard let canvas else { return }
    try require(ink_canvas_recolor_selection(canvas, rgb), operation: "Recolor selection")
  }

  func paste(_ svg: String, at point: CGPoint, placeAtPointer: Bool = false) throws {
    guard let canvas else { return }
    let data = Data(svg.utf8)
    let status = data.withUnsafeBytes { raw in
      let bytes = raw.baseAddress?.assumingMemoryBound(to: UInt8.self)
      if placeAtPointer {
        return ink_canvas_paste_at(canvas, bytes, raw.count, point.x, point.y)
      }
      return ink_canvas_paste(canvas, bytes, raw.count, point.x, point.y)
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
