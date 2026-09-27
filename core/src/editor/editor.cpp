// Live strokes follow google/ink in_progress_stroke.h:106-261 (Start,
// EnqueueInputs(real, predicted), UpdateShape, FinishInputs, CopyToStroke).
#include "editor/editor.h"

#include <chrono>
#include <cmath>
#include <cstdio>
#include <numbers>

#include "ink/brush/stock_brushes.h"
#include "ink/color/color.h"
#include "ink/geometry/affine_transform.h"
#include "ink/geometry/intersects.h"
#include "ink/geometry/segment.h"
#include "ink/strokes/stroke.h"
#include "geometry/affine.h"
#include "geometry/hit_shapes.h"
#include "layout/layout.h"
#include "strokes/clip.h"
#include "strokes/outline.h"

namespace ink_engine {
namespace {

constexpr float kBrushEpsilon = 0.01f;  // pt

ink::StrokeInput::ToolType ToolType(uint8_t tool) {
  switch (tool) {
    case INK_TOOL_MOUSE: return ink::StrokeInput::ToolType::kMouse;
    case INK_TOOL_TOUCH: return ink::StrokeInput::ToolType::kTouch;
    default: return ink::StrokeInput::ToolType::kStylus;
  }
}

// UTC "YYYY-MM-DDTHH:MM:SS.mmmZ".
std::string IsoTime(double utc_ms) {
  using namespace std::chrono;
  auto ms = milliseconds(int64_t(std::llround(utc_ms)));
  sys_days day = floor<days>(sys_time<milliseconds>(ms));
  year_month_day ymd(day);
  hh_mm_ss<milliseconds> time(ms - day.time_since_epoch());
  char text[32];
  std::snprintf(text, sizeof text, "%04d-%02u-%02uT%02lld:%02lld:%02lld.%03lldZ", int(ymd.year()),
                unsigned(ymd.month()), unsigned(ymd.day()), (long long)time.hours().count(),
                (long long)time.minutes().count(), (long long)time.seconds().count(),
                (long long)time.subseconds().count());
  return text;
}

uint32_t Channels(uint32_t has) {
  uint32_t channels = kChannelX | kChannelY | kChannelT;
  if (has & INK_HAS_PRESSURE) channels |= kChannelF;
  if (has & INK_HAS_ALTITUDE) channels |= kChannelOE;
  if (has & INK_HAS_AZIMUTH) channels |= kChannelOA;
  if (has & INK_HAS_ROLL) channels |= kChannelOR;
  return channels;
}

// Visits every element box of a layer, with a way to replace it.
bool ReplaceStroke(Elements &elements, const std::string &id, const Stroke &replacement) {
  for (size_t i = 0; i < elements.size(); ++i) {
    const Element &element = *elements[i];
    if (auto *s = std::get_if<Stroke>(&element.value); s && s->id == id) {
      elements = elements.set(i, immer::box<Element>(Element{replacement}));
      return true;
    }
    if (auto *figure = std::get_if<Figure>(&element.value)) {
      Figure revised = *figure;
      if (!ReplaceStroke(revised.children, id, replacement)) continue;
      elements = elements.set(i, immer::box<Element>(Element{std::move(revised)}));
      return true;
    }
  }
  return false;
}


constexpr uint32_t kEraserButtons = 32;  // PointerEvent.buttons bit of a pen's eraser end

// The id of a stroke or shape, the elements the erasers act on; null otherwise.
const std::string *ErasableId(const Element &element) {
  if (const auto *s = std::get_if<Stroke>(&element.value)) return &s->id;
  if (const auto *s = std::get_if<Shape>(&element.value)) return &s->id;
  return nullptr;
}

const Transform &ElementTransform(const Element &element) {
  if (const auto *s = std::get_if<Shape>(&element.value)) return s->transform;
  return std::get<Stroke>(element.value).transform;
}

// Whether the box of the segment from-to, padded by `pad`, meets the page-space
// box of an element's ink: a stroke's outline, a shape's geometry and half its
// stroke width.
bool NearInk(const Element &element, Point from, Point to, double pad) {
  const Transform &m = ElementTransform(element);
  double left = 1e300, top = 1e300, right = -1e300, bottom = -1e300;
  auto add = [&](Point p) {
    double x = m.a * p.x + m.c * p.y + m.e, y = m.b * p.x + m.d * p.y + m.f;
    left = std::min(left, x), right = std::max(right, x);
    top = std::min(top, y), bottom = std::max(bottom, y);
  };
  if (const auto *stroke = std::get_if<Stroke>(&element.value)) {
    for (const Polyline &line : stroke->outline) for (Point p : line) add(p);
  } else {
    const Shape &shape = std::get<Shape>(element.value);
    pad += shape.stroke_width / 2;
    const std::vector<Point> &p = shape.points;
    if (shape.kind == ShapeKind::kEllipse && p.size() == 2) {  // center and radii
      add({p[0].x - p[1].x, p[0].y - p[1].y});
      add({p[0].x + p[1].x, p[0].y + p[1].y});
    } else if (shape.kind == ShapeKind::kRect && p.size() == 2) {  // origin and size
      add(p[0]);
      add({p[0].x + p[1].x, p[0].y + p[1].y});
    } else {
      for (Point q : p) add(q);
      for (const Polyline &line : shape.path) for (Point q : line) add(q);
    }
  }
  return std::max(from.x, to.x) >= left - pad && std::min(from.x, to.x) <= right + pad &&
         std::max(from.y, to.y) >= top - pad && std::min(from.y, to.y) <= bottom + pad;
}

}  // namespace

const char *BrushName(InkBrush brush) {
  switch (brush) {
    case INK_BRUSH_MARKER: return "marker";
    case INK_BRUSH_HIGHLIGHTER: return "highlighter";
    default: return "pressure-pen";
  }
}

InkBrush BrushFromName(std::string_view name) {
  if (name == "marker") return INK_BRUSH_MARKER;
  if (name == "highlighter") return INK_BRUSH_HIGHLIGHTER;
  return INK_BRUSH_PRESSURE_PEN;
}

ink::Brush MakeBrush(const Pen &pen) {
  using namespace ink::stock_brushes;
  ink::BrushFamily family =
      pen.brush == INK_BRUSH_MARKER ? Marker(MarkerVersion::kV1)
      : pen.brush == INK_BRUSH_HIGHLIGHTER
          ? Highlighter(ink::BrushPaint::SelfOverlap::kDiscard, HighlighterVersion::kV1)
          : PressurePen(PressurePenVersion::kV1);
  ink::Color color = ink::Color::FromUint8(pen.color.r, pen.color.g, pen.color.b, 255);
  return *ink::Brush::Create(family, color, pen.size, kBrushEpsilon);
}

Point ToContent(const Transform &view, double x, double y) {
  Transform inverse = Inverse(view);
  return {inverse.a * x + inverse.c * y + inverse.e, inverse.b * x + inverse.d * y + inverse.f};
}

bool Editor::StartFigureCapture(size_t page, size_t layer) {
  if (figure_capture_ || live_ || erase_ || select_ || transform_ || ignored_) return false;
  const Document &doc = document();
  if (page >= doc.pages.size() || layer >= doc.pages[page]->layers.size()) return false;
  const LayerContent &content = doc.pages[page]->layers[layer];
  for (const Layer &meta : doc.notebook.layers) {
    if (meta.id == content.layer_id && (meta.hidden || meta.locked)) return false;
  }
  figure_capture_ = FigureCapture{.page = page, .layer = layer, .previous_layer = layer_,
                                  .page_id = doc.pages[page]->id,
                                  .layer_id = content.layer_id};
  layer_ = layer;
  eraser_active_ = false;
  selector_active_ = false;
  ClearSelection();
  return true;
}

Editor::FigureCaptureError Editor::FigureCaptureStatus() const {
  if (!figure_capture_) return FigureCaptureError::kNone;
  const FigureCapture &capture = *figure_capture_;
  if (capture.cross_page_input) return FigureCaptureError::kCrossPageInput;
  const Document &doc = document();
  if (capture.page >= doc.pages.size() || doc.pages[capture.page]->id != capture.page_id ||
      capture.layer >= doc.pages[capture.page]->layers.size() ||
      doc.pages[capture.page]->layers[capture.layer].layer_id != capture.layer_id) {
    return FigureCaptureError::kPageChanged;
  }
  for (size_t p = 0; p < doc.pages.size(); ++p) {
    for (size_t l = 0; l < doc.pages[p]->layers.size(); ++l) {
      for (const auto &box : doc.pages[p]->layers[l].elements) {
        const Stroke *stroke = std::get_if<Stroke>(&box->value);
        if (!stroke || !capture.stroke_ids.contains(stroke->id)) continue;
        if (p != capture.page || l != capture.layer) return FigureCaptureError::kCrossLayerMove;
      }
    }
  }
  return FigureCaptureError::kNone;
}

void Editor::AcknowledgeFigureCaptureError() {
  if (figure_capture_) figure_capture_->cross_page_input = false;
}

std::optional<std::vector<Stroke>> Editor::CapturedStrokes() const {
  if (!figure_capture_ || FigureCaptureStatus() != FigureCaptureError::kNone) return std::nullopt;
  const FigureCapture &capture = *figure_capture_;
  std::vector<Stroke> strokes;
  for (const auto &box : document().pages[capture.page]->layers[capture.layer].elements) {
    const Stroke *stroke = std::get_if<Stroke>(&box->value);
    if (stroke && capture.stroke_ids.contains(stroke->id)) strokes.push_back(*stroke);
  }
  return strokes;
}

std::optional<Figure> Editor::CompleteFigureCapture() {
  if (!figure_capture_ || live_ || erase_ || select_ || transform_ || ignored_) return std::nullopt;
  std::optional<std::vector<Stroke>> captured = CapturedStrokes();
  if (!captured) return std::nullopt;
  FigureCapture capture = *figure_capture_;
  if (captured->empty()) {
    layer_ = capture.previous_layer;
    figure_capture_.reset();
    return std::nullopt;
  }

  Document next = document();
  Page page = *next.pages[capture.page];
  Elements &elements = page.layers[capture.layer].elements;
  Elements children, grouped;
  size_t first = elements.size();
  for (size_t i = 0; i < elements.size(); ++i) {
    const Stroke *stroke = std::get_if<Stroke>(&elements[i]->value);
    if (!stroke || !capture.stroke_ids.contains(stroke->id)) continue;
    if (first == elements.size()) first = i;
    children = std::move(children).push_back(elements[i]);
  }
  Figure figure{.id = history_->ids().FigureId(), .children = std::move(children)};
  figure.scene_href = "../assets/" + figure.id + ".scene.json";
  figure.tikz_href = "../assets/" + figure.id + ".tikz";
  for (size_t i = 0; i < elements.size(); ++i) {
    if (i == first) grouped = std::move(grouped).push_back(immer::box<Element>(Element{figure}));
    const Stroke *stroke = std::get_if<Stroke>(&elements[i]->value);
    if (stroke && capture.stroke_ids.contains(stroke->id)) continue;
    grouped = std::move(grouped).push_back(elements[i]);
  }
  elements = std::move(grouped);
  next.pages = next.pages.set(capture.page, immer::box<Page>(std::move(page)));
  history_->Push(std::move(next));
  ClearSelection();
  layer_ = capture.previous_layer;
  figure_capture_.reset();
  return figure;
}

InkPenSample Editor::ToPage(InkPenSample sample, const Point &origin) const {
  Point content = ToContent(view_, sample.x, sample.y);
  sample.x = content.x - origin.x;
  sample.y = content.y - origin.y;
  return sample;
}

// InkPenSample -> ink::StrokeInput. A value without its capability bit keeps
// google/ink's kNo* sentinel (ink/strokes/input/stroke_input.h:41-100).
ink::StrokeInput Editor::ToStrokeInput(const InkPenSample &s, double t0) const {
  ink::StrokeInput input{
      .tool_type = ToolType(s.tool),
      .position = {float(s.x), float(s.y)},
      .elapsed_time = ink::Duration32::Millis(float(s.time - t0)),
  };
  if (s.has & INK_HAS_PRESSURE) input.pressure = s.pressure;
  if (s.has & INK_HAS_ALTITUDE) {
    input.tilt = ink::Angle::Radians(std::numbers::pi_v<float> / 2 - s.altitude);
  }
  if (s.has & INK_HAS_AZIMUTH) input.orientation = ink::Angle::Radians(s.azimuth);
  if (s.has & INK_HAS_ROLL) input.barrel_twist = ink::Angle::Radians(s.roll);
  return input;
}

ink::StrokeInputBatch Editor::Batch(const std::vector<InkPenSample> &samples, double t0) const {
  ink::StrokeInputBatch batch;
  for (const InkPenSample &s : samples) {
    // Append rejects inputs out of order in time or position; they are dropped,
    // as InProgressStroke::EnqueueInputs does.
    (void)batch.Append(ToStrokeInput(s, t0));
  }
  return batch;
}

void Editor::Input(const InkPenSample *samples, size_t count) {
  // A pen-down starts a gesture, which takes the samples until its end.
  bool erasing = erase_.has_value();
  bool idle = !erasing && !live_ && !select_ && !transform_ && !ignored_;
  for (size_t i = 0; i < count && idle; ++i) {
    const InkPenSample &s = samples[i];
    if (s.tool == INK_TOOL_TOUCH || s.phase == INK_PHASE_HOVER) continue;
    erasing = s.phase == INK_PHASE_BEGIN && Begin(s) == Route::kErase;
    break;
  }
  if (transform_) return TransformInput(samples, count);
  if (select_) return SelectInput(samples, count);
  if (ignored_) return IgnoreInput(samples, count);
  if (erasing) return EraseInput(samples, count);

  std::vector<InkPenSample> real, predicted;
  bool ended = false, cancelled = false;
  for (size_t i = 0; i < count; ++i) {
    const InkPenSample &s = samples[i];
    // Fingers pan and zoom (the host's job); while a pen is down they never draw.
    if (s.tool == INK_TOOL_TOUCH || s.phase == INK_PHASE_HOVER) continue;
    if (s.phase == INK_PHASE_BEGIN) {
      Point at = ToContent(view_, s.x, s.y);
      const std::vector<PagePlacement> layout = LayoutPages(document());
      const PagePlacement *placement = PageAt(layout, at.y);
      if (!placement) continue;
      if (figure_capture_ && placement->page != figure_capture_->page) {
        figure_capture_->cross_page_input = true;
        continue;
      }
      page_ = placement->page;
      live_.emplace(LiveStroke{.tool = InkTool(s.tool), .t0 = s.time, .pen = pen_,
                               .origin = {placement->x, placement->y}});
      live_->stroke.Start(MakeBrush(pen_));
    }
    if (!live_ || s.tool != live_->tool) continue;
    if (s.phase == INK_PHASE_CANCEL) {
      cancelled = true;
      break;
    }
    InkPenSample page = ToPage(s, live_->origin);
    if (s.predicted) {
      predicted.push_back(page);
    } else {
      real.push_back(page);
    }
    if (s.phase == INK_PHASE_END) {
      ended = true;
      break;
    }
  }
  if (cancelled) {
    live_.reset();
    return;
  }
  if (!live_) return;

  live_->real.insert(live_->real.end(), real.begin(), real.end());
  // The pen-up batch carries no prediction: google/ink keeps the smoothing of
  // the last real inputs over predicted ones (TRAPS.md).
  if (ended) predicted.clear();
  (void)live_->stroke.EnqueueInputs(Batch(real, live_->t0), Batch(predicted, live_->t0));
  if (!live_->real.empty()) {
    (void)live_->stroke.UpdateShape(
        ink::Duration32::Millis(float(live_->real.back().time - live_->t0)));
  }
  if (ended) Commit();
}

void Editor::Commit() {
  LiveStroke live = std::move(*live_);
  live_.reset();
  live.stroke.FinishInputs();
  (void)live.stroke.UpdateShape(ink::Duration32::Infinite());
  // Samples replaced by ink_input_update after they were enqueued: build the
  // stroke from the final samples instead.
  ink::Stroke ink_stroke = live.updated
                               ? ink::Stroke(MakeBrush(live.pen), Batch(live.real, live.t0))
                               : live.stroke.CopyToStroke();
  if (ink_stroke.GetInputs().IsEmpty()) return;

  // Only the parts on the page are kept, each its own stroke; a stroke
  // entirely off the page commits nothing.
  Document next = document();
  Page page = *next.pages[page_];
  std::vector<std::vector<InkPenSample>> pieces =
      PiecesInside(live.real, {.right = page.width, .bottom = page.height});
  if (pieces.empty()) return;
  bool whole = pieces.size() == 1 && pieces[0].size() == live.real.size() &&
               pieces[0].front().id != kInterpolatedSampleId &&
               pieces[0].back().id != kInterpolatedSampleId;
  Elements &elements = page.layers[layer_].elements;
  for (std::vector<InkPenSample> &piece : pieces) {
    double t0 = whole ? live.t0 : piece.front().time;
    ink::Stroke piece_stroke = whole ? ink_stroke : ink::Stroke(MakeBrush(live.pen), Batch(piece, t0));
    std::string id = history_->ids().StrokeId();
    auto box = immer::box<Element>(Element{MakeElement(id, piece_stroke, live.pen, t0, piece)});
    // A highlighter goes under the ink of its layer, as Write's DRAW_UNDER does
    // (syncscribble/scribblearea.cpp:1975-1976, styluslabs/Write 401b65d).
    elements = live.pen.brush == INK_BRUSH_HIGHLIGHTER ? std::move(elements).push_front(box)
                                                       : std::move(elements).push_back(box);
    committed_.push_back({id, page_, layer_, t0, live.pen, live.origin, std::move(piece)});
    if (figure_capture_) figure_capture_->stroke_ids.insert(id);
  }
  next.pages = next.pages.set(page_, immer::box<Page>(std::move(page)));
  history_->Push(std::move(next));
}

bool Editor::Erases(const InkPenSample &s) const {
  if (s.tool == INK_TOOL_TOUCH) return false;
  return s.tool == INK_TOOL_ERASER || (s.buttons & kEraserButtons) || eraser_active_;
}

void Editor::EraseInput(const InkPenSample *samples, size_t count) {
  for (size_t i = 0; i < count; ++i) {
    const InkPenSample &s = samples[i];
    if (s.tool == INK_TOOL_TOUCH || s.phase == INK_PHASE_HOVER || s.predicted) continue;
    if (s.phase == INK_PHASE_BEGIN) {
      Point at = ToContent(view_, s.x, s.y);
      const std::vector<PagePlacement> layout = LayoutPages(document());
      const PagePlacement *placement = PageAt(layout, at.y);
      if (!placement) continue;
      double scale = std::sqrt(std::abs(view_.a * view_.d - view_.b * view_.c));
      erase_.emplace(EraseGesture{.kind = eraser_kind_,
                                  .tool = InkTool(s.tool),
                                  .page = placement->page,
                                  .origin = {placement->x, placement->y},
                                  .last = {at.x - placement->x, at.y - placement->y},
                                  .radius = kEraserRadius / scale,
                                  .time = IsoTime(s.time + utc_offset_ms_),
                                  .shown = document()});
      EraseAlong(erase_->last, erase_->last);
      continue;
    }
    if (!erase_ || s.tool != erase_->tool) continue;
    if (s.phase == INK_PHASE_CANCEL) {
      erase_.reset();
      return;
    }
    InkPenSample page = ToPage(s, erase_->origin);
    Point at{page.x, page.y};
    EraseAlong(erase_->last, at);
    erase_->last = at;
    if (s.phase == INK_PHASE_END) {
      CommitErase();
      return;
    }
  }
}

const std::vector<ink::Stroke> &Editor::HitStrokes(const std::string &id, const Element &element) {
  auto [it, added] = erase_->meshes.try_emplace(id);
  if (!added) return it->second;
  if (const auto *stroke = std::get_if<Stroke>(&element.value)) {
    it->second.push_back(InkStroke(*stroke));
  } else if (const auto *shape = std::get_if<Shape>(&element.value)) {
    for (const Stroke &s : ShapeStrokes(*shape, erase_->time)) it->second.push_back(InkStroke(s));
  }
  return it->second;
}

void Editor::EraseAlong(Point from, Point to) {
  EraseGesture &g = *erase_;
  const Document &doc = document();
  const Page &page = *doc.pages[g.page];
  ink::Quad quad =
      EraserQuad({{float(from.x), float(from.y)}, {float(to.x), float(to.y)}}, float(g.radius));
  bool changed = false;
  for (size_t l = 0; l < page.layers.size(); ++l) {
    const LayerContent &layer = page.layers[l];
    auto meta = std::find_if(doc.notebook.layers.begin(), doc.notebook.layers.end(),
                             [&](const Layer &m) { return m.id == layer.layer_id; });
    if (meta != doc.notebook.layers.end() && (meta->hidden || meta->locked)) continue;
    for (const immer::box<Element> &box : layer.elements) {
      const Element &element = *box;
      const std::string *id = ErasableId(element);
      if (!id || g.hit.contains(*id) || !NearInk(element, from, to, g.radius)) continue;

      if (g.kind == INK_ERASER_STROKE) {
        // google/ink Intersects(PartitionedMesh, AffineTransform, Quad)
        // (ink/geometry/intersects.h:35-88), as in Google's Cahier sample
        // DrawingCanvasViewModel.kt; the element transform maps the mesh to the page.
        const Transform &m = ElementTransform(element);
        ink::AffineTransform to_page(float(m.a), float(m.c), float(m.e), float(m.b), float(m.d),
                                     float(m.f));
        for (const ink::Stroke &s : HitStrokes(*id, element)) {
          if (!ink::Intersects(s.GetShape(), to_page, quad)) continue;
          g.hit.insert(*id);
          changed = true;
          break;
        }
        continue;
      }

      auto found = g.free.find(*id);
      if (found == g.free.end()) {
        // A shape becomes pen strokes along its geometry, which are then cut.
        FreeErased candidate;
        if (const auto *stroke = std::get_if<Stroke>(&element.value)) {
          candidate.strokes = {*stroke};
        } else {
          candidate.strokes = ShapeStrokes(std::get<Shape>(element.value), g.time);
        }
        candidate.erased.resize(candidate.strokes.size());
        found = g.free.emplace(*id, std::move(candidate)).first;
      }
      FreeErased &f = found->second;
      for (size_t k = 0; k < f.strokes.size(); ++k) {
        ErasedSections before = f.erased[k];
        EraseCapsule(PagePath(f.strokes[k]), from, to, g.radius, f.erased[k]);
        f.stale = f.stale || f.erased[k] != before;
      }
      if (f.stale) {
        changed = true;
      } else if (std::all_of(f.erased.begin(), f.erased.end(), [](const auto &e) { return e.empty(); })) {
        g.free.erase(found);
      }
    }
  }
  if (changed) UpdateShown();
}

Page Editor::ErasedPage(IdGenerator *ids) const {
  const EraseGesture &g = *erase_;
  Page page = *document().pages[g.page];
  for (LayerContent &layer : page.layers) {
    Elements kept;
    for (const immer::box<Element> &box : layer.elements) {
      const std::string *id = ErasableId(*box);
      if (id && g.hit.contains(*id)) continue;
      auto found = id ? g.free.find(*id) : g.free.end();
      if (found == g.free.end()) {
        kept = std::move(kept).push_back(box);
        continue;
      }
      // The pieces take the original's z-position (Write element.cpp:396-446
      // getEraseSubPaths, scribblearea.cpp:1989-2017).
      for (Stroke piece : found->second.pieces) {
        if (ids) piece.id = ids->StrokeId();
        kept = std::move(kept).push_back(immer::box<Element>(Element{std::move(piece)}));
      }
    }
    layer.elements = std::move(kept);
  }
  return page;
}

void Editor::UpdateShown() {
  // Each remaining section becomes a stroke with the same brush and time
  // (Xournal++ ErasableStroke::getStrokes, Stroke::cloneSection).
  for (auto &[id, f] : erase_->free) {
    if (!f.stale) continue;
    f.stale = false;
    f.pieces.clear();
    for (size_t k = 0; k < f.strokes.size(); ++k) {
      const Stroke &base = f.strokes[k];
      for (auto [from, to] : RemainingSections(base.samples.size(), f.erased[k])) {
        Stroke piece = base;
        piece.samples = SectionSamples(base.samples, from, to);
        RebuildOutline(piece);
        f.pieces.push_back(std::move(piece));
      }
    }
  }
  Document shown = document();
  shown.pages = shown.pages.set(erase_->page, immer::box<Page>(ErasedPage(nullptr)));
  erase_->shown = std::move(shown);
}

void Editor::CommitErase() {
  if (!erase_->hit.empty() || !erase_->free.empty()) {
    Document next = document();
    next.pages = next.pages.set(erase_->page, immer::box<Page>(ErasedPage(&history_->ids())));
    history_->Push(std::move(next));
  }
  erase_.reset();
}

Stroke Editor::MakeElement(const std::string &id, const ink::Stroke &ink_stroke, const Pen &pen,
                           double t0, const std::vector<InkPenSample> &real) const {
  Stroke element{
      .id = id,
      .fill = pen.color,
      .fill_opacity = pen.opacity < 1 ? std::optional<double>(pen.opacity) : std::nullopt,
      .brush = BrushName(pen.brush),
      .brush_version = 1,
      .size = pen.size,
      .time = IsoTime(t0 + utc_offset_ms_),
      .outline = StrokeOutline(ink_stroke.GetShape()),
      .channels = Channels(real.empty() ? 0 : real.front().has),
  };
  for (const InkPenSample &s : real) {
    element.samples.push_back({.x = s.x, .y = s.y, .t = s.time - t0, .force = s.pressure,
                               .altitude = s.altitude, .azimuth = s.azimuth, .roll = s.roll});
  }
  return element;
}

void Editor::InputUpdate(const InkPenSample *samples, size_t count) {
  std::map<size_t, bool> changed;  // committed stroke index
  for (size_t i = 0; i < count; ++i) {
    auto replace = [&](std::vector<InkPenSample> &list, const Point &origin) {
      InkPenSample update = ToPage(samples[i], origin);
      for (InkPenSample &s : list) {
        if (s.id != update.id) continue;
        update.time = s.time;  // the sample keeps its place in time
        update.phase = s.phase;
        s = update;
        return true;
      }
      return false;
    };
    if (live_ && replace(live_->real, live_->origin)) {
      live_->updated = true;
      continue;
    }
    for (size_t k = committed_.size(); k-- > 0;) {
      if (replace(committed_[k].real, committed_[k].origin)) {
        changed[k] = true;
        break;
      }
    }
  }
  if (changed.empty()) return;

  // One history step for every stroke this batch changed.
  Document next = document();
  for (const auto &[k, _] : changed) {
    const CommittedStroke &c = committed_[k];
    ink::Stroke rebuilt(MakeBrush(c.pen), Batch(c.real, c.t0));
    Page page = *next.pages[c.page];
    Stroke element = MakeElement(c.id, rebuilt, c.pen, c.t0, c.real);
    if (!ReplaceStroke(page.layers[c.layer].elements, c.id, element)) continue;
    next.pages = next.pages.set(c.page, immer::box<Page>(std::move(page)));
  }
  history_->Push(std::move(next));
}

std::vector<Polyline> Editor::LiveOutline() const {
  return live_ ? ink_engine::LiveOutline(live_->stroke) : std::vector<Polyline>();
}

ink::Envelope Editor::TakeUpdatedRegion() {
  if (!live_) return {};
  ink::Envelope region = live_->stroke.GetUpdatedRegion();
  live_->stroke.ResetUpdatedRegion();
  return region;
}

}  // namespace ink_engine
