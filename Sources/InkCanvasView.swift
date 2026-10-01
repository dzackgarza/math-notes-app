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

  private var metalLayer: CAMetalLayer {
    layer as! CAMetalLayer
  }

  init(document: EngineDocument) {
    guard let device = MTLCreateSystemDefaultDevice(),
          let queue = device.makeCommandQueue()
    else {
      fatalError("Metal is unavailable")
    }
    self.device = device
    self.queue = queue

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

    var tool = InkToolSettings()
    tool.brush = UInt32(INK_BRUSH_PRESSURE_PEN.rawValue)
    tool.rgb = 0x1A1A1A
    tool.size = 1.6
    tool.opacity = 1
    check(ink_canvas_set_tool(engineCanvas, &tool), operation: "ink_canvas_set_tool")

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
    sendPencilTouches(touches, event: event)
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

  private func sendPencilTouches(_ touches: Set<UITouch>, event: UIEvent?) {
    guard let canvas else { return }

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

    guard !samples.isEmpty else { return }
    let status = samples.withUnsafeBufferPointer { buffer in
      ink_input(canvas, buffer.baseAddress, buffer.count)
    }
    check(status, operation: "ink_input")
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
