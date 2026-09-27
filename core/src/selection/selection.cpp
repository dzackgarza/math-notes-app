#include "selection/selection.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <filesystem>
#include <limits>
#include <stdexcept>

#include <boost/geometry/algorithms/simplify.hpp>
#include <boost/geometry/geometries/linestring.hpp>
#include <boost/geometry/geometries/point_xy.hpp>

#include "absl/strings/escaping.h"
#include "editor/erase.h"
#include "format/page_svg.h"
#include "geometry/affine.h"
#include "include/core/SkMatrix.h"
#include "include/core/SkFont.h"
#include "include/core/SkFontTypes.h"
#include "ink/geometry/affine_transform.h"
#include "ink/geometry/mesh.h"
#include "ink/geometry/mesh_format.h"
#include "strokes/outline.h"
#include "render/text_font.h"

namespace ink_engine {
namespace {

constexpr double kInf = std::numeric_limits<double>::infinity();

Rect Empty() { return {kInf, kInf, -kInf, -kInf}; }

void Add(Rect &r, Point p) {
  r.left = std::min(r.left, p.x), r.right = std::max(r.right, p.x);
  r.top = std::min(r.top, p.y), r.bottom = std::max(r.bottom, p.y);
}

ink::AffineTransform ToInk(const Transform &m) {
  return ink::AffineTransform(float(m.a), float(m.c), float(m.e), float(m.b), float(m.d), float(m.f));
}

Rect TextBox(const Text &text) {
  SkFont font(TextTypeface(), float(text.size));
  double width = 0;
  for (const std::string &line : text.lines) {
    width = std::max(width, double(font.measureText(line.data(), line.size(),
                                                  SkTextEncoding::kUTF8)));
  }
  double height = text.size * (1 + 1.2 * (text.lines.size() - 1));
  return {text.x, text.y - text.size, text.x + width, text.y - text.size + height};
}

// The element's hit-test meshes in its local coordinates.
std::vector<ink::PartitionedMesh> HitMeshes(const Element &element) {
  std::vector<ink::PartitionedMesh> meshes;
  if (const auto *stroke = std::get_if<Stroke>(&element.value)) {
    meshes.push_back(InkStroke(*stroke).GetShape());
  } else if (const auto *shape = std::get_if<Shape>(&element.value)) {
    for (const Stroke &s : ShapeStrokes(*shape, "")) meshes.push_back(InkStroke(s).GetShape());
  } else if (std::holds_alternative<Image>(element.value) ||
             std::holds_alternative<Text>(element.value) ||
             std::holds_alternative<Figure>(element.value)) {
    Rect bounds;
    if (const auto *image = std::get_if<Image>(&element.value)) {
      bounds = {image->x, image->y, image->x + image->width, image->y + image->height};
    } else if (const auto *figure = std::get_if<Figure>(&element.value)) {
      bounds = Empty();
      for (const auto &child : figure->children) bounds = Union(bounds, ElementBounds(*child));
      if (IsEmpty(bounds)) return meshes;
    } else {
      bounds = TextBox(std::get<Text>(element.value));
    }
    float l = float(bounds.left), t = float(bounds.top);
    float r = float(bounds.right), b = float(bounds.bottom);
    absl::StatusOr<ink::Mesh> mesh =
        ink::Mesh::Create(ink::MeshFormat(), {{l, r, r, l}, {t, t, b, b}}, {0, 1, 2, 0, 2, 3});
    if (mesh.ok()) {
      absl::StatusOr<ink::PartitionedMesh> partitioned =
          ink::PartitionedMesh::FromMeshes(absl::MakeSpan(&*mesh, 1));
      if (partitioned.ok()) meshes.push_back(*std::move(partitioned));
    }
  }
  return meshes;
}

const Transform &LocalTransform(const Element &element) {
  static const Transform kIdentity;
  if (const auto *s = std::get_if<Stroke>(&element.value)) return s->transform;
  if (const auto *s = std::get_if<Shape>(&element.value)) return s->transform;
  if (const auto *i = std::get_if<Image>(&element.value)) return i->transform;
  if (const auto *t = std::get_if<Text>(&element.value)) return t->transform;
  if (const auto *f = std::get_if<Figure>(&element.value)) return f->transform;
  return kIdentity;
}

const Elements *Children(const Element &element) {
  if (const auto *b = std::get_if<Bookmark>(&element.value)) return &b->children;
  if (const auto *f = std::get_if<Figure>(&element.value)) return &f->children;
  if (const auto *l = std::get_if<Link>(&element.value)) return &l->children;
  return nullptr;
}

template <class Visit>
Element MapChildren(const Element &element, Visit &&visit) {
  Element copy = element;
  auto remap = [&](Elements &children) {
    Elements mapped;
    for (const auto &child : children) mapped = std::move(mapped).push_back(immer::box<Element>(visit(*child)));
    children = std::move(mapped);
  };
  if (auto *b = std::get_if<Bookmark>(&copy.value)) remap(b->children);
  if (auto *f = std::get_if<Figure>(&copy.value)) remap(f->children);
  if (auto *l = std::get_if<Link>(&copy.value)) remap(l->children);
  return copy;
}

}  // namespace

// Write LassoSelector::addPoint (selection.cpp:1105-1154): each new point
// closes the path again; the chunk from simplify_start_ to the end is
// simplified, and when that removed points the next chunk starts at the
// second-to-last point. Ramer-Douglas-Peucker is Boost.Geometry's simplify
// (Write ulib/geom.h:191-210 simplifyRDP).
void LassoPath::Add(Point p, double simplify) {
  namespace bg = boost::geometry;
  using BgPoint = bg::model::d2::point_xy<double>;
  points_.push_back(p);
  if (points_.size() < 3) return;
  bg::model::linestring<BgPoint> chunk, simplified;
  for (size_t i = simplify_start_; i < points_.size(); ++i) chunk.push_back({points_[i].x, points_[i].y});
  bg::simplify(chunk, simplified, simplify);
  if (simplified.size() <= 2) return;
  points_.resize(simplify_start_);
  for (const BgPoint &q : simplified) points_.push_back({q.x(), q.y()});
  simplify_start_ = points_.size() - 2;
}

Rect Union(const Rect &a, const Rect &b) {
  return {std::min(a.left, b.left), std::min(a.top, b.top), std::max(a.right, b.right),
          std::max(a.bottom, b.bottom)};
}

bool IsEmpty(const Rect &r) { return r.left > r.right || r.top > r.bottom; }

Rect ElementBounds(const Element &element) {
  Rect bounds = Empty();
  if (const auto *figure = std::get_if<Figure>(&element.value)) {
    for (const auto &child : figure->children) bounds = Union(bounds, ElementBounds(*child));
    if (IsEmpty(bounds)) return bounds;
    Rect transformed = Empty();
    for (Point p : {Point{bounds.left, bounds.top}, Point{bounds.right, bounds.top},
                    Point{bounds.left, bounds.bottom}, Point{bounds.right, bounds.bottom}}) {
      Add(transformed, Apply(figure->transform, p));
    }
    return transformed;
  }
  if (const Elements *children = Children(element)) {
    for (const auto &child : *children) bounds = Union(bounds, ElementBounds(*child));
    return bounds;
  }
  const Transform &m = LocalTransform(element);
  if (const auto *stroke = std::get_if<Stroke>(&element.value)) {
    // Write SvgPainter::_bounds(const SvgPath *) (usvg/svgpainter.cpp:626-646):
    // the transformed centerline's box, padded by half the width times the
    // transform's average scale (ulib/geom.cpp:249-252 Transform2D::avgScale).
    // The centerline is the samples, which google/ink's smoothing keeps the
    // outline within.
    for (const Sample &s : stroke->samples) Add(bounds, Apply(m, {s.x, s.y}));
    double scale = std::sqrt(std::hypot(m.a, m.c) * std::hypot(m.b, m.d));
    double half = stroke->size / 2 * scale;
    if (!IsEmpty(bounds)) {
      bounds = {bounds.left - half, bounds.top - half, bounds.right + half, bounds.bottom + half};
    }
  } else if (const auto *shape = std::get_if<Shape>(&element.value)) {
    SkMatrix to_page = SkMatrix::MakeAll(float(m.a), float(m.c), float(m.e), float(m.b),
                                         float(m.d), float(m.f), 0, 0, 1);
    SkRect box = ShapePath(*shape).makeTransform(to_page).computeTightBounds();
    double half = shape->stroke_width / 2 * std::sqrt(std::abs(m.a * m.d - m.b * m.c));
    bounds = {box.left() - half, box.top() - half, box.right() + half, box.bottom() + half};
  } else if (const auto *image = std::get_if<Image>(&element.value)) {
    for (Point p : {Point{image->x, image->y}, Point{image->x + image->width, image->y},
                    Point{image->x, image->y + image->height},
                    Point{image->x + image->width, image->y + image->height}}) {
      Add(bounds, Apply(m, p));
    }
  } else if (const auto *text = std::get_if<Text>(&element.value)) {
    Rect box = TextBox(*text);
    for (Point p : {Point{box.left, box.top}, Point{box.right, box.top},
                    Point{box.left, box.bottom}, Point{box.right, box.bottom}}) {
      Add(bounds, Apply(m, p));
    }
  }
  return bounds;
}

bool InsideRect(const Element &element, const Rect &rect) {
  Rect b = ElementBounds(element);
  return !IsEmpty(b) && b.left >= rect.left && b.right <= rect.right && b.top >= rect.top &&
         b.bottom <= rect.bottom;
}

bool LassoSelects(const ink::PartitionedMesh &lasso, const Element &element) {
  if (!std::holds_alternative<Figure>(element.value)) {
    if (const Elements *children = Children(element)) {
      return !children->empty() && std::all_of(children->begin(), children->end(),
                                              [&](const auto &c) { return LassoSelects(lasso, *c); });
    }
  }
  std::vector<ink::PartitionedMesh> meshes = HitMeshes(element);
  if (meshes.empty()) return false;
  ink::AffineTransform lasso_to_local = ToInk(Inverse(LocalTransform(element)));
  return std::all_of(meshes.begin(), meshes.end(), [&](const ink::PartitionedMesh &mesh) {
    return mesh.CoverageIsGreaterThan(lasso, kLassoCoverage, lasso_to_local);
  });
}

// Write RectSelector::shrink (selection.cpp:727-741).
Rect SelectionRect(const Rect &bounds, double scale) {
  double padx = (4 * kHandlePad / scale - (bounds.right - bounds.left)) / 2;
  double pady = (4 * kHandlePad / scale - (bounds.bottom - bounds.top)) / 2;
  padx = std::max(kSelectionMinPad, padx + kSelectionMinPad);
  pady = std::max(kSelectionMinPad, pady + kSelectionMinPad);
  return {bounds.left - padx, bounds.top - pady, bounds.right + padx, bounds.bottom + pady};
}

Point RotateHandle(const Rect &rect, double scale) {
  return {(rect.left + rect.right) / 2, rect.top - 6 * kHandleSize / scale};
}

// Write ScribbleArea::selectionHit (scribblearea.cpp:1345-1377) with
// RectSelector::scaleHandleHit and rotHandleHit (selection.cpp:748-778).
HandleHit HitSelection(const Rect &rect, Point p, double scale, bool touch) {
  double h = touch ? 2 * kHandleSize : kHandleSize;
  double a = (h + 3) / scale;
  auto near = [&](Point c) { return p.x >= c.x - a && p.x <= c.x + a && p.y >= c.y - a && p.y <= c.y + a; };
  const Point corners[4][2] = {
      {{rect.left, rect.top}, {rect.right, rect.bottom}},
      {{rect.right, rect.top}, {rect.left, rect.bottom}},
      {{rect.left, rect.bottom}, {rect.right, rect.top}},
      {{rect.right, rect.bottom}, {rect.left, rect.top}},
  };
  for (const auto &[corner, opposite] : corners) {
    if (!near(corner)) continue;
    // The bottom-right corner scales with a fixed aspect ratio; the others freely.
    return {HandleKind::kScale, opposite, opposite.x < p.x && opposite.y < p.y};
  }
  if (near(RotateHandle(rect, scale))) {
    return {HandleKind::kRotate, {(rect.left + rect.right) / 2, (rect.top + rect.bottom) / 2}};
  }
  if (p.x >= rect.left && p.x <= rect.right && p.y >= rect.top && p.y <= rect.bottom) {
    return {HandleKind::kMove};
  }
  return {};
}

Element Transformed(const Element &element, const Transform &m) {
  if (const auto *figure = std::get_if<Figure>(&element.value)) {
    Figure copy = *figure;
    copy.transform = Compose(m, copy.transform);
    return Element{std::move(copy)};
  }
  if (Children(element)) return MapChildren(element, [&](const Element &c) { return Transformed(c, m); });
  Element copy = element;
  std::visit(
      [&](auto &e) {
        using T = std::decay_t<decltype(e)>;
        if constexpr (std::is_same_v<T, Stroke> || std::is_same_v<T, Shape> ||
                      std::is_same_v<T, Image> || std::is_same_v<T, Text>) {
          e.transform = Compose(m, e.transform);
        }
      },
      copy.value);
  return copy;
}

namespace {

// The id field of an element that has one; a link has none.
template <class E>
auto IdOf(E &element) -> decltype(&std::get<Stroke>(element.value).id) {
  using Id = decltype(&std::get<Stroke>(element.value).id);
  return std::visit(
      [](auto &e) -> Id {
        using T = std::decay_t<decltype(e)>;
        if constexpr (std::is_same_v<T, Link>) {
          return nullptr;
        } else {
          return &e.id;
        }
      },
      element.value);
}

std::string NewId(const Element &element, IdGenerator &ids) {
  if (std::holds_alternative<Bookmark>(element.value)) return ids.BookmarkId();
  if (std::holds_alternative<Figure>(element.value)) return ids.FigureId();
  return ids.StrokeId();
}

}  // namespace

Element WithNewIds(const Element &element, IdGenerator &ids) {
  Element copy = MapChildren(element, [&](const Element &c) { return WithNewIds(c, ids); });
  if (std::string *id = IdOf(copy)) *id = NewId(copy, ids);
  return copy;
}

Element WithFreeIds(const Element &element, const std::vector<std::string> &taken, IdGenerator &ids) {
  Element copy = MapChildren(element, [&](const Element &c) { return WithFreeIds(c, taken, ids); });
  std::string *id = IdOf(copy);
  if (id && (std::holds_alternative<Figure>(copy.value) ||
             std::find(taken.begin(), taken.end(), *id) != taken.end())) *id = NewId(copy, ids);
  return copy;
}

void CollectIds(const Elements &elements, std::vector<std::string> &ids) {
  for (const auto &box : elements) {
    if (const std::string *id = IdOf(*box)) ids.push_back(*id);
    if (const Elements *children = Children(*box)) CollectIds(*children, ids);
  }
}

namespace {

constexpr std::string_view kDataPrefix = "data:";

std::string MediaType(const std::string &path) {
  std::string ext = std::filesystem::path(path).extension().string();
  if (ext == ".jpg" || ext == ".jpeg") return "image/jpeg";
  return "image/png";
}

std::string Extension(std::string_view media_type) {
  return media_type == "image/jpeg" ? ".jpg" : ".png";
}

template <class VisitImage, class VisitFigure>
Element MapAssets(const Element &element, VisitImage &visit_image, VisitFigure &visit_figure) {
  if (Children(element)) {
    Element copy = MapChildren(element, [&](const Element &c) {
      return MapAssets(c, visit_image, visit_figure);
    });
    if (auto *figure = std::get_if<Figure>(&copy.value)) visit_figure(*figure);
    return copy;
  }
  Element copy = element;
  if (auto *image = std::get_if<Image>(&copy.value)) visit_image(*image);
  return copy;
}

std::string InlineAsset(const std::string &page_file, const std::string &href,
                        const std::string &media_type, const Assets &assets) {
  std::string path = NotebookPath(page_file, href);
  auto file = assets.find(path);
  if (file == assets.end()) throw std::runtime_error("figure asset is missing: " + path);
  std::string_view bytes(static_cast<const char *>(file->second->data()), file->second->size());
  return std::string(kDataPrefix) + media_type + ";base64," + absl::Base64Escape(bytes);
}

std::string DecodeFigureAsset(std::string_view encoded) {
  size_t comma = encoded.find(',');
  if (!encoded.starts_with(kDataPrefix) || comma == std::string_view::npos ||
      !encoded.substr(0, comma).ends_with(";base64")) {
    throw std::invalid_argument("figure clipboard asset must be inline");
  }
  std::string bytes;
  if (!absl::Base64Unescape(encoded.substr(comma + 1), &bytes)) {
    throw std::invalid_argument("figure clipboard asset is not valid base64");
  }
  return bytes;
}

std::string StoreFigureAsset(std::string bytes, const std::string &page_file,
                             const std::string &id, const std::string &extension,
                             Assets &assets, NotebookFiles &added) {
  namespace fs = std::filesystem;
  std::string stem = "assets/" + id;
  std::string path = stem + extension;
  for (int n = 2; assets.contains(path); ++n) {
    path = stem + "-" + std::to_string(n) + extension;
  }
  assets[path] = SkData::MakeWithCopy(bytes.data(), bytes.size());
  added[path] = std::move(bytes);
  return fs::path(path).lexically_relative(fs::path(page_file).parent_path()).generic_string();
}

}  // namespace

Element InlineImages(const Element &element, const std::string &page_file, const Assets &assets) {
  auto image = [&](Image &image) {
    std::string path = NotebookPath(page_file, image.href);
    auto file = assets.find(path);
    if (file == assets.end()) return;
    std::string_view bytes(static_cast<const char *>(file->second->data()), file->second->size());
    image.href = std::string(kDataPrefix) + MediaType(path) + ";base64," + absl::Base64Escape(bytes);
  };
  auto figure = [&](Figure &figure) {
    figure.scene_href = InlineAsset(page_file, figure.scene_href, "application/json", assets);
    figure.tikz_href = InlineAsset(page_file, figure.tikz_href, "text/plain", assets);
  };
  return MapAssets(element, image, figure);
}

Element StoreImages(const Element &element, const std::string &page_file, Assets &assets,
                    NotebookFiles &added) {
  namespace fs = std::filesystem;
  auto image = [&](Image &image) {
    std::string_view href = image.href;
    size_t comma = href.find(',');
    if (!href.starts_with(kDataPrefix) || comma == std::string_view::npos ||
        !href.substr(0, comma).ends_with(";base64")) {
      return;
    }
    std::string bytes;
    if (!absl::Base64Unescape(href.substr(comma + 1), &bytes)) return;
    std::string_view media_type = href.substr(kDataPrefix.size(), href.find(';') - kDataPrefix.size());
    sk_sp<SkData> data = SkData::MakeWithCopy(bytes.data(), bytes.size());
    std::string path;
    for (const auto &[name, file] : assets) {
      if (file->equals(data.get())) path = name;
    }
    if (path.empty()) {
      // A name from the content; a different file under that name gets a suffix.
      char hash[17];
      std::snprintf(hash, sizeof hash, "%016zx", std::hash<std::string>{}(bytes));
      path = "assets/" + std::string(hash) + Extension(media_type);
      for (int n = 2; assets.contains(path); ++n) {
        path = "assets/" + std::string(hash) + "-" + std::to_string(n) + Extension(media_type);
      }
      assets[path] = data;
      added[path] = std::move(bytes);
    }
    image.href = fs::path(path).lexically_relative(fs::path(page_file).parent_path()).generic_string();
  };
  auto figure = [&](Figure &figure) {
    std::string scene = DecodeFigureAsset(figure.scene_href);
    std::string tikz = DecodeFigureAsset(figure.tikz_href);
    figure.scene_href = StoreFigureAsset(std::move(scene), page_file, figure.id,
                                          ".scene.json", assets, added);
    figure.tikz_href = StoreFigureAsset(std::move(tikz), page_file, figure.id,
                                         ".tikz", assets, added);
  };
  return MapAssets(element, image, figure);
}

std::string ClipboardSvg(const Elements &elements, const std::string &layer_id) {
  Rect bounds = Empty();
  for (const auto &box : elements) bounds = Union(bounds, ElementBounds(*box));
  Page page{.id = "clipboard",
            .width = std::max(1.0, std::ceil(bounds.right)),
            .height = std::max(1.0, std::ceil(bounds.bottom)),
            .layers = {LayerContent{layer_id, elements}}};
  return WritePage(page);
}

std::optional<Elements> ReadClipboard(std::string_view svg) {
  Page page = ReadPage(svg, "clipboard.svg", {});
  if (page.error) return std::nullopt;
  Elements elements;
  for (const LayerContent &layer : page.layers) elements = elements + layer.elements;
  return elements;
}

}  // namespace ink_engine
