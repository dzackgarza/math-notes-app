import CoreGraphics
import InkEngine
import Metal
import QuartzCore

final class MetalInputTestHarness {
  let canvas: OpaquePointer
  private let device: MTLDevice
  private let queue: MTLCommandQueue
  private let layer: CAMetalLayer
  private var nextID: UInt32 = 1

  @MainActor
  init(document: EngineDocument, size: CGSize = CGSize(width: 1200, height: 2000)) throws {
    guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
      throw EngineDocumentError.operation("Create test canvas", "Metal is unavailable")
    }
    let layer = CAMetalLayer()
    layer.device = device
    layer.pixelFormat = .bgra8Unorm
    layer.framebufferOnly = true
    layer.drawableSize = size

    var created: OpaquePointer?
    let status = ink_canvas_create_metal(
      document.pointer,
      Unmanaged.passUnretained(device).toOpaque(),
      Unmanaged.passUnretained(queue).toOpaque(),
      Unmanaged.passUnretained(layer).toOpaque(),
      &created)
    guard status == INK_OK, let created else {
      throw EngineDocumentError.operation("Create test canvas", EngineDocument.lastError())
    }
    self.device = device
    self.queue = queue
    self.layer = layer
    canvas = created

    guard ink_canvas_set_surface_size(canvas, Int32(size.width), Int32(size.height), 1) == INK_OK,
      ink_canvas_set_view(canvas, 1, 0, 0, 1, 0, 0) == INK_OK
    else {
      ink_canvas_free(canvas)
      throw EngineDocumentError.operation("Configure test canvas", EngineDocument.lastError())
    }
  }

  deinit {
    ink_canvas_free(canvas)
  }

  @MainActor
  func setTool(_ tool: InkToolSettings) throws {
    var settings = tool
    guard ink_canvas_set_tool(canvas, &settings) == INK_OK else {
      throw EngineDocumentError.operation("Set test tool", EngineDocument.lastError())
    }
  }

  @MainActor
  func setSelector(_ selector: InkSelector) throws {
    guard ink_canvas_set_selector(canvas, selector, 1) == INK_OK else {
      throw EngineDocumentError.operation("Set test selector", EngineDocument.lastError())
    }
  }

  @MainActor
  func drag(from: CGPoint, to: CGPoint, startTime: Double) throws {
    let distance = hypot(to.x - from.x, to.y - from.y)
    let steps = max(2, Int(ceil(distance / 10)))
    for index in 0...steps {
      let fraction = Double(index) / Double(steps)
      var sample = InkPenSample()
      sample.x = from.x + (to.x - from.x) * fraction
      sample.y = from.y + (to.y - from.y) * fraction
      sample.time = startTime + Double(index) * 10
      sample.pressure = 0.5
      sample.id = nextID
      nextID &+= 1
      sample.tool = UInt8(INK_TOOL_PEN.rawValue)
      sample.phase = UInt8((index == 0
        ? INK_PHASE_BEGIN
        : index == steps ? INK_PHASE_END : INK_PHASE_MOVE).rawValue)
      guard ink_input(canvas, &sample, 1) == INK_OK else {
        throw EngineDocumentError.operation("Send test input", EngineDocument.lastError())
      }
    }
  }
}
