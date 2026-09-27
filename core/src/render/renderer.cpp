#include "render/renderer.h"

#include <algorithm>
#include <cmath>
#include <filesystem>
#include <unordered_set>

#include "include/codec/SkCodec.h"
#include "include/codec/SkPngDecoder.h"
#include "include/codec/SkJpegDecoder.h"
#include "include/core/SkCanvas.h"
#include "include/core/SkColorSpace.h"
#include "include/core/SkFont.h"
#include "include/core/SkFontTypes.h"
#include "include/core/SkPaint.h"
#include "include/core/SkPathBuilder.h"
#include "include/effects/SkDashPathEffect.h"
#include "include/gpu/ganesh/GrDirectContext.h"
#include "include/gpu/ganesh/SkSurfaceGanesh.h"
#include "selection/selection.h"
#include "render/text_font.h"
#include "strokes/outline.h"

namespace ink_engine {
namespace {

SkMatrix ToSkMatrix(const Transform &t) {
  return SkMatrix::MakeAll(float(t.a), float(t.c), float(t.e), float(t.b), float(t.d), float(t.f),
                           0, 0, 1);
}

SkColor ToSkColor(Rgb rgb, double opacity = 1) {
  return SkColorSetARGB(uint8_t(std::lround(opacity * 255)), rgb.r, rgb.g, rgb.b);
}

// SVG stroke defaults: butt caps, miter joins, miter limit 4.
SkPaint StrokePaint(Rgb color, double width) {
  SkPaint paint(SkColor4f::FromColor(ToSkColor(color)));
  paint.setAntiAlias(true);
  paint.setStyle(SkPaint::kStroke_Style);
  paint.setStrokeWidth(float(width));
  paint.setStrokeMiter(4);
  return paint;
}

// Draws a shape as Chromium draws the SVG element: rect and ellipse with
// their own canvas calls, whose thin-stroke rasterization differs from a
// path's; the rest as paths (third_party/blink/renderer/core/paint/
// svg_shape_painter.cc, SVGShapePainter::FillShape and StrokeShape).
void DrawShape(SkCanvas *canvas, const Shape &shape, const SkPath &path) {
  SkPaint paint = StrokePaint(shape.stroke, shape.stroke_width);
  SkRect rect;
  switch (shape.kind) {
    case ShapeKind::kRect:
      if (path.isRect(&rect)) return canvas->drawRect(rect, paint);
      break;
    case ShapeKind::kEllipse:
      if (path.isOval(&rect)) return canvas->drawOval(rect, paint);
      break;
    default:
      break;
  }
  canvas->drawPath(path, paint);
}

SkPaint FillPaint(Rgb color, double opacity = 1) {
  SkPaint paint(SkColor4f::FromColor(ToSkColor(color, opacity)));
  paint.setAntiAlias(true);
  return paint;
}

void CollectElements(const Elements &elements, std::unordered_set<const Element *> *out) {
  for (const auto &box : elements) {
    out->insert(&*box);
    if (auto *b = std::get_if<Bookmark>(&box->value)) CollectElements(b->children, out);
    if (auto *f = std::get_if<Figure>(&box->value)) CollectElements(f->children, out);
    if (auto *l = std::get_if<Link>(&box->value)) CollectElements(l->children, out);
  }
}

}  // namespace

sk_sp<SkImage> Renderer::Asset(const std::string &page_file, const std::string &href) {
  std::string path = NotebookPath(page_file, href);
  auto bytes = assets_->find(path);
  // A missing or undecodable file draws nothing, as in an SVG viewer.
  if (bytes == assets_->end()) return nullptr;
  DecodedAsset &decoded = images_[path];
  if (decoded.bytes != bytes->second) {
    decoded.bytes = bytes->second;
    auto codec = path.ends_with(".jpg") || path.ends_with(".jpeg")
                     ? SkJpegDecoder::Decode(bytes->second, nullptr, nullptr)
                     : SkPngDecoder::Decode(bytes->second, nullptr, nullptr);
    decoded.image = codec ? std::get<0>(codec->getImage()) : nullptr;
  }
  return decoded.image;
}

const Renderer::CachedElement &Renderer::Cached(const immer::box<Element> &box) {
  auto found = elements_.find(&*box);
  if (found != elements_.end()) return found->second;
  CachedElement entry{box, SkPath(), SkRect::MakeEmpty()};
  std::visit(
      [&](const auto &e) {
        using T = std::decay_t<decltype(e)>;
        if constexpr (std::is_same_v<T, Stroke>) {
          entry.path = OutlinePath(e.outline);
          entry.bounds = ToSkMatrix(e.transform).mapRect(entry.path.getBounds());
        } else if constexpr (std::is_same_v<T, Shape>) {
          entry.path = ShapePath(e);
          // A miter reaches at most miter limit × half the width past a vertex.
          float outset = float(e.stroke_width) * 2;
          entry.bounds =
              ToSkMatrix(e.transform).mapRect(entry.path.getBounds().makeOutset(outset, outset));
        } else if constexpr (std::is_same_v<T, Image>) {
          entry.bounds = ToSkMatrix(e.transform)
                             .mapRect(SkRect::MakeXYWH(float(e.x), float(e.y), float(e.width),
                                                       float(e.height)));
        } else if constexpr (std::is_same_v<T, Text>) {
          Rect bounds = ink_engine::ElementBounds(*box);
          entry.bounds = SkRect::MakeLTRB(float(bounds.left), float(bounds.top),
                                         float(bounds.right), float(bounds.bottom));
        } else if constexpr (std::is_same_v<T, Figure>) {
          SkRect children = SkRect::MakeEmpty();
          for (const auto &child : e.children) children.join(Cached(child).bounds);
          entry.bounds = ToSkMatrix(e.transform).mapRect(children);
        } else {
          for (const auto &child : e.children) entry.bounds.join(Cached(child).bounds);
        }
      },
      box->value);
  return elements_.emplace(&*box, std::move(entry)).first->second;
}

SkMatrix Renderer::ContentMatrix() const {
  return SkMatrix::Scale(view_.pixel_ratio, view_.pixel_ratio) *
         ToSkMatrix(view_.content_to_view);
}

bool Renderer::Update(const Document &document, const View &view, bool live_changed) {
  std::vector<PagePlacement> layout = LayoutPages(document);
  bool document_changed = !document_ || !(document_->pages == document.pages) ||
                          !(document_->notebook == document.notebook);
  bool full = !content_ || invalidated_ || !(view == view_) || layout != layout_ ||
              !(document_->notebook == document.notebook);
  invalidated_ = false;
  SkRegion dirty;
  if (!full && document_changed) dirty = DirtyRegion(document);

  if (full && document_changed && document_) {
    std::unordered_set<const Element *> present;
    for (const auto &page : document.pages) {
      for (const LayerContent &layer : page->layers) CollectElements(layer.elements, &present);
    }
    std::erase_if(elements_, [&](const auto &entry) { return !present.contains(entry.first); });
  }

  if (!content_ || view.width != view_.width || view.height != view_.height) {
    SkImageInfo info = SkImageInfo::MakeN32Premul(view.width, view.height, SkColorSpace::MakeSRGB());
    content_ = context_ ? SkSurfaces::RenderTarget(context_, skgpu::Budgeted::kYes, info)
                        : SkSurfaces::Raster(info);
  }
  document_ = document;
  layout_ = std::move(layout);
  view_ = view;

  if (full) {
    Redraw(SkRegion(SkIRect::MakeWH(view.width, view.height)));
    ++stats_.full_redraws;
  } else if (!dirty.isEmpty()) {
    Redraw(dirty);
    ++stats_.partial_redraws;
  }
  if (live_changed) screen_stale_ = true;
  return screen_stale_;
}

// Device-space areas of the content surface that `next` changes: the bounds
// of every element added or removed, and whole pages whose paper changed.
SkRegion Renderer::DirtyRegion(const Document &next) {
  SkRegion region;
  SkMatrix content = ContentMatrix();
  for (const PagePlacement &placement : layout_) {
    const auto &before = document_->pages[placement.page];
    const auto &after = next.pages[placement.page];
    if (&*before == &*after) continue;
    SkMatrix to_device = content * SkMatrix::Translate(float(placement.x), float(placement.y));
    auto add = [&](const SkRect &page_rect) {
      // Antialiasing reaches one pixel past the geometry.
      region.op(to_device.mapRect(page_rect).roundOut().makeOutset(2, 2), SkRegion::kUnion_Op);
    };
    if (!(before->background == after->background) ||
        before->layers.size() != after->layers.size()) {
      add(SkRect::MakeWH(float(after->width), float(after->height)));
      continue;
    }
    for (size_t l = 0; l < after->layers.size(); ++l) {
      std::unordered_set<const Element *> old_set, new_set;
      for (const auto &box : before->layers[l].elements) old_set.insert(&*box);
      for (const auto &box : after->layers[l].elements) new_set.insert(&*box);
      for (const auto &box : after->layers[l].elements) {
        if (!old_set.contains(&*box)) add(Cached(box).bounds);
      }
      for (const auto &box : before->layers[l].elements) {
        if (new_set.contains(&*box)) continue;
        add(Cached(box).bounds);
        elements_.erase(&*box);
      }
      // Reordering alone changes what is on top.
      if (old_set == new_set && !(before->layers[l].elements == after->layers[l].elements)) {
        for (const auto &box : after->layers[l].elements) add(Cached(box).bounds);
      }
    }
  }
  region.op(SkIRect::MakeWH(view_.width, view_.height), SkRegion::kIntersect_Op);
  return region;
}

void Renderer::Redraw(const SkRegion &region) {
  SkCanvas *canvas = content_->getCanvas();
  canvas->save();
  canvas->clipRegion(region);
  canvas->clear(kDeskColor);
  SkMatrix content = ContentMatrix();
  SkMatrix inverse;
  if (content.invert(&inverse)) {
    SkRect clip_content = inverse.mapRect(SkRect::Make(region.getBounds()));
    for (const PagePlacement &placement : layout_) {
      SkRect page_rect = SkRect::MakeXYWH(float(placement.x), float(placement.y),
                                          float(placement.width), float(placement.height));
      if (!SkRect::Intersects(page_rect, clip_content)) continue;
      canvas->setMatrix(content * SkMatrix::Translate(page_rect.x(), page_rect.y()));
      DrawPage(canvas, *document_->pages[placement.page],
               clip_content.makeOffset(-page_rect.x(), -page_rect.y()));
    }
  }
  canvas->restore();
  for (SkRegion::Iterator it(region); !it.done(); it.next()) {
    stats_.redrawn_pixels += uint64_t(it.rect().width()) * uint64_t(it.rect().height());
  }
  screen_stale_ = true;
}

void Renderer::DrawPageForExport(SkCanvas *canvas, const Document &document, const Page &page,
                                 bool include_hidden_layers) {
  document_ = document;
  DrawPage(canvas, page, SkRect::MakeWH(float(page.width), float(page.height)),
           include_hidden_layers);
}

void Renderer::DrawPage(SkCanvas *canvas, const Page &page, const SkRect &cull,
                        bool include_hidden_layers) {
  const Background &bg = page.background;
  // g#background in file order: the paper, the imported page image, the ruling.
  canvas->drawRect(SkRect::MakeWH(float(page.width), float(page.height)), FillPaint(bg.fill));
  if (bg.image) DrawImage(canvas, page, *bg.image);
  for (const RulingPath &line : bg.lines) {
    if (line.round_caps) {
      // SVG 2 §13.6.3 (zero-length subpaths): a round cap paints a circle
      // whose diameter is the stroke width. Filled, as browsers paint it.
      SkPathBuilder dots;
      std::vector<Polyline> strokes;
      for (const Polyline &p : line.d) {
        bool zero = !p.empty() && std::all_of(p.begin(), p.end(), [&](const Point &q) { return q == p[0]; });
        if (zero) {
          dots.addCircle(float(p[0].x), float(p[0].y), float(line.stroke_width / 2));
        } else {
          strokes.push_back(p);
        }
      }
      canvas->drawPath(dots.detach(), FillPaint(line.stroke));
      SkPaint paint = StrokePaint(line.stroke, line.stroke_width);
      paint.setStrokeCap(SkPaint::kRound_Cap);
      canvas->drawPath(OpenPath(strokes), paint);
      continue;
    }
    canvas->drawPath(OpenPath(line.d), StrokePaint(line.stroke, line.stroke_width));
  }
  const std::vector<Layer> &layers = document_->notebook.layers;
  for (const LayerContent &content : page.layers) {
    auto layer = std::find_if(layers.begin(), layers.end(),
                              [&](const Layer &l) { return l.id == content.layer_id; });
    if (!include_hidden_layers && layer != layers.end() && layer->hidden) continue;
    DrawElements(canvas, page, content.elements, cull);
  }
}

void Renderer::DrawElements(SkCanvas *canvas, const Page &page, const Elements &elements,
                            const SkRect &cull) {
  for (const auto &box : elements) {
    const CachedElement &cached = Cached(box);
    if (!SkRect::Intersects(cached.bounds, cull)) continue;
    std::visit(
        [&](const auto &e) {
          using T = std::decay_t<decltype(e)>;
          if constexpr (std::is_same_v<T, Stroke>) {
            SkPaint paint = FillPaint(e.fill, e.fill_opacity.value_or(1));
            canvas->save();
            canvas->concat(ToSkMatrix(e.transform));
            canvas->drawPath(cached.path, paint);
            canvas->restore();
            ++stats_.elements_drawn;
          } else if constexpr (std::is_same_v<T, Shape>) {
            canvas->save();
            canvas->concat(ToSkMatrix(e.transform));
            DrawShape(canvas, e, cached.path);
            canvas->restore();
            ++stats_.elements_drawn;
          } else if constexpr (std::is_same_v<T, Image>) {
            DrawImage(canvas, page, e);
            ++stats_.elements_drawn;
          } else if constexpr (std::is_same_v<T, Text>) {
            canvas->save();
            canvas->concat(ToSkMatrix(e.transform));
            SkFont font(TextTypeface(), float(e.size));
            SkPaint paint = FillPaint(e.fill);
            for (size_t i = 0; i < e.lines.size(); ++i) {
              const std::string &line = e.lines[i];
              canvas->drawSimpleText(line.data(), line.size(), SkTextEncoding::kUTF8,
                                     float(e.x), float(e.y + i * e.size * 1.2), font, paint);
            }
            canvas->restore();
            ++stats_.elements_drawn;
          } else if constexpr (std::is_same_v<T, Figure>) {
            canvas->save();
            canvas->concat(ToSkMatrix(e.transform));
            DrawElements(canvas, page, e.children, SkRect::MakeLTRB(-1e9f, -1e9f, 1e9f, 1e9f));
            canvas->restore();
          } else {
            DrawElements(canvas, page, e.children, cull);
          }
        },
        box->value);
  }
}

void Renderer::DrawImage(SkCanvas *canvas, const Page &page, const Image &image) {
  sk_sp<SkImage> decoded = Asset(page.file, image.href);
  if (!decoded) return;
  canvas->save();
  canvas->concat(ToSkMatrix(image.transform));
  // SVG preserveAspectRatio defaults to xMidYMid meet.
  SkRect box = SkRect::MakeXYWH(float(image.x), float(image.y), float(image.width),
                                float(image.height));
  float scale = std::min(box.width() / decoded->width(), box.height() / decoded->height());
  SkRect dst = SkRect::MakeXYWH(0, 0, decoded->width() * scale, decoded->height() * scale);
  dst.offset(box.centerX() - dst.centerX(), box.centerY() - dst.centerY());
  canvas->drawImageRect(decoded, dst, SkSamplingOptions(SkFilterMode::kLinear, SkMipmapMode::kLinear));
  canvas->restore();
}

void Renderer::Draw(SkCanvas *screen, const LiveInk *live, const SelectionOverlay *overlay) {
  screen->save();
  screen->resetMatrix();
  content_->draw(screen, 0, 0);
  auto place = [&](size_t page) {
    for (const PagePlacement &p : layout_) {
      if (p.page != page) continue;
      screen->setMatrix(ContentMatrix() * SkMatrix::Translate(float(p.x), float(p.y)));
      return true;
    }
    return false;
  };
  if (live && place(live->page)) {
    screen->drawPath(OutlinePath(live->outline), FillPaint(live->color, live->opacity));
  }
  if (overlay && place(overlay->page)) DrawOverlay(screen, *overlay);
  screen->restore();
  screen_stale_ = false;
  ++stats_.frames;
}

// The selection marks in the accent color of docs/specs/tablet-ui.md ("Visual
// style"): dashed lasso, rectangle and frame, round handles, as GoodNotes and
// Noteful draw them. Sizes are in view units.
void Renderer::DrawOverlay(SkCanvas *screen, const SelectionOverlay &overlay) {
  const Rgb accent{0x2F, 0x6F, 0xEB};
  const float unit = float(1 / overlay.view_scale);  // one view unit in pt
  SkPaint dashed = StrokePaint(accent, 1.5 * unit);
  const float intervals[] = {5 * unit, 4 * unit};
  dashed.setPathEffect(SkDashPathEffect::Make(intervals, 0));

  if (!overlay.floating.empty()) {
    const Page &page = *document_->pages[overlay.page];
    screen->save();
    screen->concat(ToSkMatrix(overlay.live));
    DrawElements(screen, page, overlay.floating, SkRect::MakeLTRB(-1e9f, -1e9f, 1e9f, 1e9f));
    screen->restore();
  }
  if (overlay.lasso.size() > 1) {
    SkPathBuilder lasso;
    lasso.moveTo(float(overlay.lasso[0].x), float(overlay.lasso[0].y));
    for (const Point &p : overlay.lasso) lasso.lineTo(float(p.x), float(p.y));
    lasso.close();
    SkPath path = lasso.detach();
    screen->drawPath(path, FillPaint(accent, 0.06));
    screen->drawPath(path, dashed);
  }
  if (overlay.band) {
    const Rect &r = *overlay.band;
    SkRect band = SkRect::MakeLTRB(float(r.left), float(r.top), float(r.right), float(r.bottom)).makeSorted();
    screen->drawRect(band, FillPaint(accent, 0.06));
    screen->drawRect(band, dashed);
  }
  if (!overlay.frame) return;
  const Rect &r = *overlay.frame;
  SkMatrix live = ToSkMatrix(overlay.live);
  SkPoint corners[4] = {{float(r.left), float(r.top)}, {float(r.right), float(r.top)},
                        {float(r.right), float(r.bottom)}, {float(r.left), float(r.bottom)}};
  live.mapPoints(corners);
  SkPathBuilder frame;
  frame.addPolygon(corners, /*close=*/true);
  screen->drawPath(frame.detach(), dashed);
  if (!overlay.handles) return;
  SkPaint fill = FillPaint({255, 255, 255});
  SkPaint ring = StrokePaint(accent, 1.5 * unit);
  auto handle = [&](SkPoint at) {
    screen->drawCircle(at, 5 * unit, fill);
    screen->drawCircle(at, 5 * unit, ring);
  };
  SkPoint top = {float((r.left + r.right) / 2), float(r.top)};
  SkPoint rotate = {float(overlay.rotate_handle.x), float(overlay.rotate_handle.y)};
  screen->drawLine(top, rotate, StrokePaint(accent, 1 * unit));
  for (SkPoint corner : corners) handle(corner);
  handle(rotate);
}

}  // namespace ink_engine

namespace ink_engine {

std::string NotebookPath(const std::string &page_file, const std::string &href) {
  namespace fs = std::filesystem;
  return (fs::path(page_file).parent_path() / href).lexically_normal().generic_string();
}

}  // namespace ink_engine
