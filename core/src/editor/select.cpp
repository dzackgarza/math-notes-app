// The selection tools on the editor: lasso and rectangle select, and moving,
// scaling and rotating the selection with its handles, after Write's
// ScribbleArea (syncscribble/scribblearea.cpp, styluslabs/Write 401b65d):
// doPressEvent 1417-1460 (selectionHit, clearing the selection), 1560-1567,
// doMoveEvent 1716-1832, doReleaseEvent 2019-2139 (commit; a drop on another
// page moves the selection there at the same absolute position,
// 2091-2131), and the clipboard of scribbledoc.cpp:723-760 and
// ScribbleArea::doPasteAt (711-781).
#include <algorithm>
#include <cmath>

#include "editor/editor.h"
#include "geometry/affine.h"
#include "geometry/hit_shapes.h"
#include "layout/layout.h"
#include "selection/ruled.h"
#include "document/reflow.h"

namespace ink_engine {
namespace {

// Whether the layer's elements can be selected: not hidden, not locked.
bool Selectable(const Document &doc, const LayerContent &layer) {
  auto meta = std::find_if(doc.notebook.layers.begin(), doc.notebook.layers.end(),
                           [&](const Layer &m) { return m.id == layer.layer_id; });
  return meta == doc.notebook.layers.end() || !(meta->hidden || meta->locked);
}

bool Meets(const Rect &a, const Rect &b) {
  return a.left <= b.right && b.left <= a.right && a.top <= b.bottom && b.top <= a.bottom;
}

Rect Bounds(const Elements &elements) {
  Rect bounds{1, 1, 0, 0};
  bool first = true;
  for (const auto &box : elements) {
    Rect b = ElementBounds(*box);
    if (IsEmpty(b)) continue;
    bounds = first ? b : Union(bounds, b);
    first = false;
  }
  return bounds;
}

// The page placement whose rectangle holds content point `p`.
const PagePlacement *PageContaining(const std::vector<PagePlacement> &layout, Point p) {
  for (const PagePlacement &placement : layout) {
    if (p.x >= placement.x && p.x <= placement.x + placement.width && p.y >= placement.y &&
        p.y <= placement.y + placement.height) {
      return &placement;
    }
  }
  return nullptr;
}

const PagePlacement *Placement(const std::vector<PagePlacement> &layout, size_t page) {
  for (const PagePlacement &placement : layout) {
    if (placement.page == page) return &placement;
  }
  return nullptr;
}

// The page without the elements `items` refers to.
Page Without(Page page, const std::vector<ElementRef> &items) {
  for (size_t k = items.size(); k-- > 0;) {
    Elements &elements = page.layers[items[k].layer].elements;
    elements = elements.erase(items[k].index);
  }
  return page;
}

// Write doPressEvent for MODE_SELECTRULED and MODE_ERASERULED
// (scribblearea.cpp:1398-1400, 1539-1547, 1560-1563). A blank page gets
// Write's lines with the pen-down in the middle of one.
RuledDrag BeginRuled(const Document &doc, const Page &page, Point at) {
  RuledDrag drag{.page = page, .grid = WorkingGrid(page, at.y)};
  drag.page.background.ruling = Ruling::kLined;
  drag.page.background.y_ruling = drag.grid.spacing;
  drag.page.background.y_offset = drag.grid.offset;
  for (auto &layer : drag.page.layers) {
    if (!Selectable(doc, layer)) layer.elements = {};
  }
  drag.grouped = GroupStrokes(drag.page, drag.grid.spacing);
  drag.line = drag.grid.Line(at.y);
  drag.min = drag.max = at.x;
  return drag;
}

// Write doMoveEvent for MODE_ERASERULED (scribblearea.cpp:1697-1712): the
// part of the current line that the pen has passed. In the left margin, the
// lines from that part to the pen, as ruled select takes them.
RuledRange EraseRange(RuledDrag &drag, Point pen) {
  if (pen.x < drag.page.background.margin_left) {
    const Point from{drag.min, drag.grid.Top(drag.line) + drag.grid.spacing / 2};
    return MakeRuledRange(drag.grid, from, pen, {});
  }
  const int line = drag.grid.Line(pen.y);
  if (line != drag.line) drag.min = drag.max = pen.x;
  drag.line = line;
  drag.min = std::min(drag.min, pen.x);
  drag.max = std::max(drag.max, pen.x);
  return MakeRuledRange(drag.grid, {drag.min, pen.y}, {drag.max, pen.y}, {});
}

// Write doMoveEvent (scribblearea.cpp:1697-1724). Ruled select takes what the
// range from the pen-down to the pen holds. Ruled erase keeps what it has
// taken and adds what its range touches.
void MoveRuled(RuledDrag &drag, bool erase, Point start, Point pen) {
  RuledRange range = erase ? EraseRange(drag, pen) : MakeRuledRange(drag.page, start, pen);
  std::vector<ElementRef> items;
  for (size_t layer = 0; layer < drag.page.layers.size(); ++layer) {
    const Elements &elements = drag.page.layers[layer].elements;
    for (size_t index = 0; index < elements.size(); ++index) {
      const ElementRef item{layer, index};
      if ((erase && std::binary_search(drag.items.begin(), drag.items.end(), item)) ||
          InRuledRange(*elements[index], range, drag.grouped, erase)) {
        items.push_back(item);
      }
    }
  }
  drag.items = std::move(items);
  if (!erase) drag.range = std::move(range);
}

// Appends `elements` to the layer `layer_id` of `page` (added when the page
// has no such layer); returns their references.
std::vector<ElementRef> Append(Page &page, const std::string &layer_id, const Elements &elements) {
  auto layer = std::find_if(page.layers.begin(), page.layers.end(),
                            [&](const LayerContent &l) { return l.layer_id == layer_id; });
  if (layer == page.layers.end()) {
    page.layers.push_back({layer_id, {}});
    layer = page.layers.end() - 1;
  }
  std::vector<ElementRef> items;
  for (const auto &box : elements) {
    items.push_back({size_t(layer - page.layers.begin()), layer->elements.size()});
    layer->elements = std::move(layer->elements).push_back(box);
  }
  return items;
}

std::vector<std::string> TextLines(std::string_view utf8) {
  std::vector<std::string> lines;
  while (true) {
    size_t end = utf8.find('\n');
    lines.emplace_back(utf8.substr(0, end));
    if (end == std::string_view::npos) break;
    utf8.remove_prefix(end + 1);
  }
  return lines;
}

// The oval selector's loop: the ellipse inscribed in the rectangle from `a`
// to `b`, as SkPath::addOval defines it, sampled at 64 points of the
// parametric form (x0 + rx cos t, y0 + ry sin t).
std::vector<Point> OvalPoints(Point a, Point b) {
  constexpr int kSegments = 64;
  const Point center{(a.x + b.x) / 2, (a.y + b.y) / 2};
  const double rx = std::abs(b.x - a.x) / 2, ry = std::abs(b.y - a.y) / 2;
  std::vector<Point> points;
  for (int i = 0; i < kSegments; ++i) {
    const double t = 2 * M_PI * i / kSegments;
    points.push_back({center.x + rx * std::cos(t), center.y + ry * std::sin(t)});
  }
  return points;
}

}  // namespace

double Editor::ViewScale() const { return std::sqrt(std::abs(view_.a * view_.d - view_.b * view_.c)); }

const Selection *Editor::CurrentSelection() {
  if (!selection_) return nullptr;
  const Document &doc = document();
  if (selection_->page < doc.pages.size() && &*doc.pages[selection_->page] == &*selection_->value &&
      std::all_of(selection_->items.begin(), selection_->items.end(), [&](const ElementRef &item) {
        return Selectable(doc, selection_->value->layers[item.layer]);
      })) {
    return &*selection_;
  }
  selection_.reset();
  ++overlay_version_;
  return nullptr;
}

std::optional<int> Editor::AlignmentStep() {
  const Selection *selection = CurrentSelection();
  if (!selection || selection->line_spacing <= 0 || !transform_ ||
      transform_->hit.kind != HandleKind::kMove || !transform_->live.IsTranslation()) {
    return std::nullopt;
  }
  return int(std::lround(transform_->live.f / selection->line_spacing));
}

void Editor::ClearSelection() {
  if (!selection_) return;
  selection_.reset();
  ++overlay_version_;
}

// Write scribblearea.cpp:1128-1170 groups authored content without flattening it.
void Editor::BookmarkSelection() {
  const Selection *selection = CurrentSelection();
  if (!selection) throw std::invalid_argument("select content to bookmark");
  const size_t layer = selection->items.front().layer;
  for (const auto &item : selection->items)
    if (item.layer != layer) throw std::invalid_argument("select content on one layer to group it");
  const size_t index = selection->page;
  Bookmark bookmark{history_->ids().BookmarkId(), Selected(*selection)};
  Page page = Without(*selection->value, selection->items);
  auto items = Append(page, page.layers[layer].layer_id,
                      Elements{immer::box<Element>(Element{std::move(bookmark)})});
  Document next = document();
  next.pages = next.pages.set(index, immer::box<Page>(std::move(page)));
  PushSelection(std::move(next), index, std::move(items));
}

void Editor::LinkSelection(const std::string &href) {
  if (href.empty()) throw std::invalid_argument("choose a link destination");
  const Selection *selection = CurrentSelection();
  if (!selection) throw std::invalid_argument("select content for the link");
  const size_t layer = selection->items.front().layer;
  for (const auto &item : selection->items)
    if (item.layer != layer) throw std::invalid_argument("select content on one layer to group it");
  const size_t index = selection->page;
  Elements children;
  for (const auto &element : Selected(*selection)) {
    if (const auto *link = std::get_if<Link>(&element->value)) {
      for (const auto &child : link->children) children = children.push_back(child);
    } else children = children.push_back(element);
  }
  Page page = Without(*selection->value, selection->items);
  auto items = Append(page, page.layers[layer].layer_id,
                      Elements{immer::box<Element>(Element{Link{href, children}})});
  Document next = document();
  next.pages = next.pages.set(index, immer::box<Page>(std::move(page)));
  PushSelection(std::move(next), index, std::move(items));
}

void Editor::AddBookmark(double x, double y) {
  if (!ResolveActiveLayer()) throw std::invalid_argument("choose an editable layer");
  Document next = document();
  const auto layout = Layout(next);
  const Point point = ToContent(view_, x, y);
  const auto *placement = PageContaining(layout, point);
  if (!placement) throw std::invalid_argument("choose a point on a page");
  Page page = *next.pages[placement->page];
  if (layer_ >= page.layers.size() || !Selectable(next, page.layers[layer_]))
    throw std::invalid_argument("choose an editable layer");
  // Write scribblearea.cpp:1504-1532 margin flag; Write units converted to pt.
  constexpr double w = 7.68, h = 14.4;
  const auto grid = WorkingGrid(page, point.y - placement->y);
  const double top = grid.Top(grid.Line(point.y - placement->y)) + (grid.spacing - h) / 2;
  Shape flag{.id = history_->ids().StrokeId(), .kind = ShapeKind::kPolygon,
             .transform = Translation(std::max(0.0, page.background.margin_left - 1.5 * w), top),
             .stroke = pen_.color, .stroke_width = 1,
             .points = {{0, 0}, {w, 0}, {w, h}, {w / 2, 5 * h / 6}, {0, h}}};
  Bookmark bookmark{history_->ids().BookmarkId(), Elements{immer::box<Element>(Element{flag})}};
  auto items = Append(page, page.layers[layer_].layer_id,
                      Elements{immer::box<Element>(Element{std::move(bookmark)})});
  next.pages = next.pages.set(placement->page, immer::box<Page>(std::move(page)));
  PushSelection(std::move(next), placement->page, std::move(items));
}

void Editor::UngroupSelection() {
  const auto *selection = CurrentSelection();
  if (!selection) return;
  const size_t index = selection->page;
  Page page = *selection->value;
  std::vector<ElementRef> items;
  bool changed = false;
  for (size_t l = 0; l < page.layers.size(); ++l) {
    Elements result;
    for (size_t i = 0; i < page.layers[l].elements.size(); ++i) {
      const auto &element = page.layers[l].elements[i];
      const bool selected = std::find(selection->items.begin(), selection->items.end(), ElementRef{l, i}) != selection->items.end();
      const Elements *children = nullptr;
      if (selected) {
        if (const auto *b = std::get_if<Bookmark>(&element->value)) children = &b->children;
        if (const auto *link = std::get_if<Link>(&element->value)) children = &link->children;
      }
      if (children) {
        for (const auto &child : *children) {
          items.push_back({l, result.size()});
          result = result.push_back(child);
        }
        changed = true;
      } else {
        if (selected) items.push_back({l, result.size()});
        result = result.push_back(element);
      }
    }
    page.layers[l].elements = std::move(result);
  }
  if (!changed) return;
  Document next = document();
  next.pages = next.pages.set(index, immer::box<Page>(std::move(page)));
  PushSelection(std::move(next), index, std::move(items));
}

Elements Editor::Selected(const Selection &selection) const {
  Elements elements;
  for (const ElementRef &item : selection.items) {
    elements = std::move(elements).push_back(selection.value->layers[item.layer].elements[item.index]);
  }
  return elements;
}

void Editor::PushSelection(Document next, size_t page, std::vector<ElementRef> items) {
  history_->Push(std::move(next));
  const immer::box<Page> &value = document().pages[page];
  selection_ = Selection{.page = page, .value = value, .items = std::move(items)};
  selection_->rect = SelectionRect(Bounds(Selected(*selection_)), ViewScale());
  ++overlay_version_;
}

// Write doPressEvent: a pen-down on the selection's page hits its handles or
// its inside first; anywhere else it clears the selection, and a pen stroke
// that clears it draws nothing (clearSelOnly, scribblearea.cpp:1428-1431).
Editor::Route Editor::Begin(const InkPenSample &s) {
  Point at = ToContent(view_, s.x, s.y);
  const std::vector<PagePlacement> layout = Layout(document());
  const PagePlacement *placement = PageAt(layout, at);
  if (!placement) return Erases(s) ? Route::kErase : Route::kDraw;
  Point p{at.x - placement->x, at.y - placement->y};
  if (const Selection *selection = CurrentSelection()) {
    HandleHit hit;
    if (selection->page == placement->page) {
      hit = HitSelection(selection->rect, p, ViewScale(), false);
    }
    // Write's mode order: the handles, then the eraser, then moving the selection.
    const bool erases = Erases(s) || (selector_active_ && selector_kind_ == INK_SELECTOR_RULED_ERASE);
    if (hit.kind == HandleKind::kScale || hit.kind == HandleKind::kRotate ||
        (hit.kind == HandleKind::kMove && !erases)) {
      Document shown = document();
      shown.pages = shown.pages.set(selection->page,
                                    immer::box<Page>(Without(*selection->value, selection->items)));
      transform_.emplace(TransformGesture{.hit = hit, .tool = InkTool(s.tool),
                                          .origin = {placement->x, placement->y}, .initial = p,
                                          .shown = std::move(shown)});
      ++overlay_version_;
      return Route::kTransform;
    }
    ClearSelection();
    if (!Erases(s) && !selector_active_) {
      ignored_ = InkTool(s.tool);
      return Route::kIgnore;
    }
  }
  if (Erases(s)) return Route::kErase;
  if (!selector_active_) return Route::kDraw;
  select_.emplace(SelectGesture{.kind = selector_kind_, .tool = InkTool(s.tool),
                                .page = placement->page, .origin = {placement->x, placement->y},
                                .start = p, .last = p});
  select_->lasso.Add(p, kLassoSimplify / ViewScale());
  if (selector_kind_ == INK_SELECTOR_RULED || selector_kind_ == INK_SELECTOR_RULED_ERASE) {
    select_->ruled = BeginRuled(document(), *document().pages[placement->page], p);
  }
  if (selector_kind_ >= INK_SELECTOR_SPACE_VERTICAL && selector_kind_ <= INK_SELECTOR_SPACE_RULED) {
    const auto mode = selector_kind_ == INK_SELECTOR_SPACE_VERTICAL ? SpaceMode::kVertical
        : selector_kind_ == INK_SELECTOR_SPACE_HORIZONTAL ? SpaceMode::kHorizontal : SpaceMode::kRuled;
    select_->space = BeginInsertSpace(document(), placement->page, p, mode);
  }
  ++overlay_version_;
  return Route::kSelect;
}

void Editor::IgnoreInput(const InkPenSample *samples, size_t count) {
  for (size_t i = 0; i < count; ++i) {
    const InkPenSample &s = samples[i];
    if (s.tool != *ignored_ || s.phase == INK_PHASE_HOVER) continue;
    if (s.phase == INK_PHASE_END || s.phase == INK_PHASE_CANCEL) ignored_.reset();
  }
}

void Editor::SelectInput(const InkPenSample *samples, size_t count) {
  for (size_t i = 0; i < count; ++i) {
    const InkPenSample &s = samples[i];
    if (s.tool != select_->tool || s.phase == INK_PHASE_HOVER || s.predicted) continue;
    if (s.phase == INK_PHASE_CANCEL) {
      select_.reset();
      ++overlay_version_;
      return;
    }
    if (s.phase == INK_PHASE_BEGIN) continue;
    Point at = ToContent(view_, s.x, s.y);
    Point p{at.x - select_->origin.x, at.y - select_->origin.y};
    // Write doMoveEvent: a lasso point closer than 2 view units to the last
    // one is dropped (scribblearea.cpp:1725-1730).
    bool lasso = select_->kind == INK_SELECTOR_LASSO;
    double moved = std::hypot(p.x - select_->last.x, p.y - select_->last.y);
    if (!lasso || moved >= kLassoMinPointDistance / ViewScale()) {
      if (lasso) select_->lasso.Add(p, kLassoSimplify / ViewScale());
      select_->last = p;
      // Write takes no action for a pen event at the last position
      // (scribblearea.cpp:1650-1652).
      if (select_->ruled && moved > 0) {
        const bool erase = select_->kind == INK_SELECTOR_RULED_ERASE;
        MoveRuled(*select_->ruled, erase, select_->start, p);
        if (erase) {
          Document shown = document();
          shown.pages = shown.pages.set(
              select_->page, immer::box<Page>(Without(*shown.pages[select_->page], select_->ruled->items)));
          select_->shown = std::move(shown);
        }
      }
      if (select_->space) {
        // Write moves the ink at each pen event (scribblearea.cpp:1833-1885).
        // A copy of the generator gives an added page the id that the
        // release gives it.
        IdGenerator ids = history_->ids();
        select_->shown = InsertSpace(document(), *select_->space, p, ids, template_page_);
      }
      ++overlay_version_;
    }
    if (s.phase == INK_PHASE_END) return FinishSelect();
  }
}

// Write doReleaseEvent for MODE_SELECTLASSO and MODE_SELECTRECT: the elements
// the lasso covers, or whose bounds the rectangle holds, become the selection.
void Editor::FinishSelect() {
  SelectGesture g = std::move(*select_);
  select_.reset();
  ++overlay_version_;
  const Document &doc = document();
  const Page &page = *doc.pages[g.page];

  if (g.space) {
    // Write doReleaseEvent (scribblearea.cpp:2163-2193): the moved ink is
    // committed and the ink under a drag up or left is deleted.
    Document next = InsertSpace(doc, *g.space, g.last, history_->ids(), template_page_);
    if (!(next == doc)) history_->Push(std::move(next));
    return;
  }

  if (g.ruled) {
    // Write doReleaseEvent (scribblearea.cpp:2014-2028): ruled erase deletes
    // what it took; ruled select keeps it as a selection that moves by lines.
    if (g.ruled->items.empty()) return;
    selection_ = Selection{.page = g.page, .value = doc.pages[g.page], .items = std::move(g.ruled->items),
                           .line_spacing = g.ruled->grid.spacing};
    selection_->rect = SelectionRect(Bounds(Selected(*selection_)), ViewScale());
    if (g.kind == INK_SELECTOR_RULED_ERASE) DeleteSelection();
    return;
  }

  Rect area{std::min(g.start.x, g.last.x), std::min(g.start.y, g.last.y),
            std::max(g.start.x, g.last.x), std::max(g.start.y, g.last.y)};
  std::optional<ink::PartitionedMesh> lasso;
  if (g.kind == INK_SELECTOR_LASSO || g.kind == INK_SELECTOR_OVAL) {
    std::vector<ink::Point> points;
    area = {1, 1, 0, 0};
    for (Point p : g.kind == INK_SELECTOR_OVAL ? OvalPoints(g.start, g.last) : g.lasso.points()) {
      points.push_back({float(p.x), float(p.y)});
      area = IsEmpty(area) ? Rect{p.x, p.y, p.x, p.y} : Union(area, {p.x, p.y, p.x, p.y});
    }
    absl::StatusOr<ink::PartitionedMesh> mesh = LassoMesh(points);
    if (!mesh.ok()) return;
    lasso = *std::move(mesh);
  }

  std::vector<ElementRef> items;
  for (size_t l = 0; l < page.layers.size(); ++l) {
    if (!Selectable(doc, page.layers[l])) continue;
    const Elements &elements = page.layers[l].elements;
    for (size_t i = 0; i < elements.size(); ++i) {
      const Element &element = *elements[i];
      bool hit = lasso ? Meets(ElementBounds(element), area) && LassoSelects(*lasso, element)
                       : InsideRect(element, area);
      if (hit) items.push_back({l, i});
    }
  }
  if (items.empty()) return;
  selection_ = Selection{.page = g.page, .value = doc.pages[g.page], .items = std::move(items)};
  selection_->rect = SelectionRect(Bounds(Selected(*selection_)), ViewScale());
}

void Editor::TransformInput(const InkPenSample *samples, size_t count) {
  for (size_t i = 0; i < count; ++i) {
    const InkPenSample &s = samples[i];
    if (s.tool != transform_->tool || s.phase == INK_PHASE_HOVER || s.predicted) continue;
    if (s.phase == INK_PHASE_CANCEL || !CurrentSelection()) {
      // Write: the selection returns to where it was and stays selected.
      transform_.reset();
      ++overlay_version_;
      return;
    }
    if (s.phase == INK_PHASE_BEGIN) continue;
    Point at = ToContent(view_, s.x, s.y);
    UpdateTransform({at.x - transform_->origin.x, at.y - transform_->origin.y});
    if (s.phase == INK_PHASE_END) return CommitTransform(at);
  }
}

// Write doMoveEvent (scribblearea.cpp:1735-1756, 1806-1832): scale factors
// from the pen-down to the pen relative to the opposite corner, the bottom
// right corner keeping the ratio, each at least 0.01 in size; the rotation by
// the angle the pen turned about the center; a move by the pen's offset. The
// transform is taken from the pen-down, where Write composes one step per
// event.
void Editor::UpdateTransform(Point at) {
  TransformGesture &g = *transform_;
  const Point &o = g.hit.origin;
  switch (g.hit.kind) {
    case HandleKind::kScale: {
      double sx = (at.x - o.x) / (g.initial.x - o.x);
      double sy = (at.y - o.y) / (g.initial.y - o.y);
      if (g.hit.lock_ratio) {
        double s = std::max(0.01, std::min(std::abs(sx), std::abs(sy)));
        sx = std::copysign(s, sx);
        sy = std::copysign(s, sy);
      }
      if (std::abs(sx) < 0.01) sx = std::copysign(0.01, sx);
      if (std::abs(sy) < 0.01) sy = std::copysign(0.01, sy);
      g.live = ScaleAbout(sx, sy, o);
      break;
    }
    case HandleKind::kRotate:
      g.live = RotateAbout(std::atan2(at.y - o.y, at.x - o.x) -
                               std::atan2(g.initial.y - o.y, g.initial.x - o.x),
                           o);
      break;
    default: {
      double dy = at.y - g.initial.y;
      if (selection_ && selection_->line_spacing > 0) dy = std::round(dy / selection_->line_spacing) * selection_->line_spacing;
      g.live = Translation(at.x - g.initial.x, dy);
    }
  }
  ++overlay_version_;
}

// Write doReleaseEvent (scribblearea.cpp:2045-2139): the transform becomes
// one history step. A move dropped on another page takes the selection to
// that page at the same absolute position; dropped off every page, it
// returns.
void Editor::CommitTransform(Point content) {
  TransformGesture g = std::move(*transform_);
  transform_.reset();
  ++overlay_version_;
  const Selection selection = *selection_;
  if (g.live.IsIdentity()) return;
  Document next = document();
  const std::vector<PagePlacement> layout = Layout(next);
  size_t target = selection.page;
  if (g.hit.kind == HandleKind::kMove) {
    const PagePlacement *drop = PageContaining(layout, content);
    if (!drop) return;
    target = drop->page;
  }

  Elements moved;
  for (const auto &box : Selected(selection)) {
    moved = std::move(moved).push_back(immer::box<Element>(Transformed(*box, g.live)));
  }
  if (target == selection.page) {
    Page page = *selection.value;
    for (size_t k = 0; k < selection.items.size(); ++k) {
      const ElementRef &item = selection.items[k];
      Elements &elements = page.layers[item.layer].elements;
      elements = elements.set(item.index, moved[k]);
    }
    next.pages = next.pages.set(target, immer::box<Page>(std::move(page)));
    PushSelection(std::move(next), target, selection.items);
    selection_->line_spacing = selection.line_spacing;
    return;
  }

  // Write pastes the moved elements at the end of the target page's layer.
  const PagePlacement *from = Placement(layout, selection.page);
  const PagePlacement *to = Placement(layout, target);
  Transform shift = Translation(from->x - to->x, from->y - to->y);
  Page source = Without(*selection.value, selection.items);
  Page page = *next.pages[target];
  std::vector<ElementRef> items;
  for (size_t k = 0; k < selection.items.size(); ++k) {
    const std::string &layer_id = selection.value->layers[selection.items[k].layer].layer_id;
    Elements one{immer::box<Element>(Transformed(*moved[k], shift))};
    std::vector<ElementRef> added = Append(page, layer_id, one);
    items.insert(items.end(), added.begin(), added.end());
  }
  next.pages = next.pages.set(selection.page, immer::box<Page>(std::move(source)));
  next.pages = next.pages.set(target, immer::box<Page>(std::move(page)));
  std::sort(items.begin(), items.end(), [](const ElementRef &a, const ElementRef &b) {
    return a.layer != b.layer ? a.layer < b.layer : a.index < b.index;
  });
  PushSelection(std::move(next), target, std::move(items));
  selection_->line_spacing = selection.line_spacing;
}

void Editor::SelectAll(size_t page_index) {
  const Document &doc = document();
  if (page_index >= doc.pages.size()) return;
  const Page &page = *doc.pages[page_index];
  std::vector<ElementRef> items;
  for (size_t l = 0; l < page.layers.size(); ++l) {
    if (!Selectable(doc, page.layers[l])) continue;
    for (size_t i = 0; i < page.layers[l].elements.size(); ++i) items.push_back({l, i});
  }
  ClearSelection();
  if (items.empty()) return;
  selection_ = Selection{.page = page_index, .value = doc.pages[page_index], .items = std::move(items)};
  selection_->rect = SelectionRect(Bounds(Selected(*selection_)), ViewScale());
  ++overlay_version_;
}

bool Editor::DeleteSelection() {
  const Selection *selection = CurrentSelection();
  if (!selection) return false;
  Document next = document();
  next.pages = next.pages.set(selection->page,
                              immer::box<Page>(Without(*selection->value, selection->items)));
  ClearSelection();
  history_->Push(std::move(next));
  return true;
}

std::string Editor::CopySelection(bool cut, const Assets &assets) {
  const Selection *selection = CurrentSelection();
  if (!selection) return {};
  Elements elements;
  for (const auto &box : Selected(*selection)) {
    Element element = InlineImages(*box, selection->value->file, assets);
    elements = std::move(elements).push_back(
        immer::box<Element>(cut ? std::move(element) : WithNewIds(element, history_->ids())));
  }
  const std::string &layer_id = selection->value->layers[selection->items[0].layer].layer_id;
  std::string svg = ClipboardSvg(elements, layer_id);
  if (cut) DeleteSelection();
  return svg;
}

bool Editor::Paste(std::string_view svg, double x, double y, double view_width, double view_height,
                   Assets &assets, NotebookFiles &added, bool place_at_pointer) {
  if (!ResolveActiveLayer()) return false;
  std::optional<Elements> pasted = ReadClipboard(svg);
  if (!pasted) return false;
  if (pasted->empty()) return false;
  Document next = document();
  const std::vector<PagePlacement> layout = Layout(next);
  Point at = ToContent(view_, x, y);
  const PagePlacement *placement = PageAt(layout, at);
  if (!placement) return false;
  Page page = *next.pages[placement->page];

  std::vector<std::string> taken;
  for (const LayerContent &layer : page.layers) CollectIds(layer.elements, taken);
  Elements elements;
  for (const auto &box : *pasted) {
    Element element = StoreImages(WithFreeIds(*box, taken, history_->ids()), page.file, assets, added);
    elements = std::move(elements).push_back(immer::box<Element>(std::move(element)));
  }

  // Write ScribbleArea::doPasteAt (scribblearea.cpp:738-750): the content
  // keeps its place when it is in view (ScribbleView::isVisible,
  // scribbleview.cpp:247-250: it overlaps the screen) and its center and top
  // left corner are on the page; otherwise its center goes to (x, y), kept
  // half a ruling inside the page.
  Rect b = Bounds(elements);
  auto on_page = [&](double px, double py) {
    return px >= 0 && px <= page.width && py >= 0 && py <= page.height;
  };
  Point view_a = ToContent(view_, 0, 0), view_b = ToContent(view_, view_width, view_height);
  Rect screen{std::min(view_a.x, view_b.x) - placement->x, std::min(view_a.y, view_b.y) - placement->y,
              std::max(view_a.x, view_b.x) - placement->x, std::max(view_a.y, view_b.y) - placement->y};
  bool visible = b.left <= screen.right && screen.left <= b.right && b.top <= screen.bottom &&
                 screen.top <= b.bottom;
  Point center{(b.left + b.right) / 2, (b.top + b.bottom) / 2};
  if (!IsEmpty(b) && (place_at_pointer || !(visible && on_page(center.x, center.y) && on_page(b.left, b.top)))) {
    double w = b.right - b.left, h = b.bottom - b.top;
    double xr = page.background.x_ruling, yr = page.background.y_ruling;
    Point p{at.x - placement->x, at.y - placement->y};
    double cx = std::min(std::max(xr / 2 + w / 2, p.x), page.width - xr / 2 - w / 2);
    double cy = std::min(std::max(yr / 2 + h / 2, p.y), page.height - yr / 2 - h / 2);
    Elements moved;
    for (const auto &box : elements) {
      moved = std::move(moved).push_back(
          immer::box<Element>(Transformed(*box, Translation(cx - center.x, cy - center.y))));
    }
    elements = std::move(moved);
  }
  std::vector<ElementRef> items = Append(page, page.layers[layer_].layer_id, elements);
  next.pages = next.pages.set(placement->page, immer::box<Page>(std::move(page)));
  PushSelection(std::move(next), placement->page, std::move(items));
  return true;
}

void Editor::DuplicateSelection(Assets &assets, NotebookFiles &added) {
  const Selection *selection = CurrentSelection();
  if (!selection) return;
  Document next = document();
  Page page = *selection->value;
  std::vector<ElementRef> items;
  for (const ElementRef &item : selection->items) {
    const Element &original = *page.layers[item.layer].elements[item.index];
    Element copy = InlineImages(original, page.file, assets);
    copy = StoreImages(WithNewIds(copy, history_->ids()), page.file, assets, added);
    copy = Transformed(copy, Translation(kDuplicateOffset, kDuplicateOffset));
    std::vector<ElementRef> added =
        Append(page, page.layers[item.layer].layer_id, Elements{immer::box<Element>(std::move(copy))});
    items.insert(items.end(), added.begin(), added.end());
  }
  size_t index = selection->page;
  next.pages = next.pages.set(index, immer::box<Page>(std::move(page)));
  PushSelection(std::move(next), index, std::move(items));
}

bool Editor::RecolorSelection(Rgb color) {
  const Selection *selection = CurrentSelection();
  if (!selection) return false;
  Document next = document();
  Page page = *selection->value;
  for (const ElementRef &item : selection->items) {
    Elements &elements = page.layers[item.layer].elements;
    elements = elements.set(item.index, immer::box<Element>(Recolored(*elements[item.index], color)));
  }
  size_t index = selection->page;
  std::vector<ElementRef> items = selection->items;
  next.pages = next.pages.set(index, immer::box<Page>(std::move(page)));
  PushSelection(std::move(next), index, std::move(items));
  return true;
}

bool Editor::InsertText(std::string_view utf8, double x, double y, TextBoxStyle style) {
  if (!ResolveActiveLayer()) return false;
  if (utf8.empty()) return false;
  Document next = document();
  const std::vector<PagePlacement> layout = Layout(next);
  Point at = ToContent(view_, x, y);
  const PagePlacement *placement = PageContaining(layout, at);
  if (!placement) return false;
  Page page = *next.pages[placement->page];
  if (page.layers.empty() || layer_ >= page.layers.size() ||
      !Selectable(next, page.layers[layer_])) return false;
  Text text{.id = history_->ids().StrokeId(),
            .x = at.x - placement->x,
            .y = at.y - placement->y + 18,
            .width = style.width, .rtl = style.rtl,
            .lines = TextLines(utf8)};
  std::vector<ElementRef> items = Append(page, page.layers[layer_].layer_id,
                                          Elements{immer::box<Element>(Element{text})});
  next.pages = next.pages.set(placement->page, immer::box<Page>(std::move(page)));
  PushSelection(std::move(next), placement->page, std::move(items));
  return true;
}

bool Editor::SelectTextAt(double x, double y) {
  const Document &doc = document();
  Point at = ToContent(view_, x, y);
  const std::vector<PagePlacement> layout = Layout(doc);
  const PagePlacement *placement = PageContaining(layout, at);
  if (!placement) {
    ClearSelection();
    return false;
  }
  const Page &page = *doc.pages[placement->page];
  Point local{at.x - placement->x, at.y - placement->y};
  for (size_t l = page.layers.size(); l-- > 0;) {
    if (!Selectable(doc, page.layers[l])) continue;
    const Elements &elements = page.layers[l].elements;
    for (size_t i = elements.size(); i-- > 0;) {
      if (!std::holds_alternative<Text>(elements[i]->value)) continue;
      Rect bounds = ElementBounds(*elements[i]);
      if (local.x < bounds.left || local.x > bounds.right ||
          local.y < bounds.top || local.y > bounds.bottom) continue;
      selection_ = Selection{.page = placement->page, .value = doc.pages[placement->page],
                             .items = {{l, i}}};
      selection_->rect = SelectionRect(bounds, ViewScale());
      ++overlay_version_;
      return true;
    }
  }
  ClearSelection();
  return false;
}

std::optional<std::string> Editor::SelectedText() {
  const Selection *selection = CurrentSelection();
  if (!selection || selection->items.size() != 1) return std::nullopt;
  const ElementRef &item = selection->items.front();
  const Text *text = std::get_if<Text>(&selection->value->layers[item.layer].elements[item.index]->value);
  if (!text) return std::nullopt;
  std::string utf8;
  for (size_t i = 0; i < text->lines.size(); ++i) {
    if (i > 0) utf8 += '\n';
    utf8 += text->lines[i];
  }
  return utf8;
}

const Text *Editor::SelectedTextValue() {
  const auto *selection = CurrentSelection();
  if (!selection || selection->items.size() != 1) return nullptr;
  const auto &item = selection->items.front();
  return std::get_if<Text>(&selection->value->layers[item.layer].elements[item.index]->value);
}

bool Editor::SetSelectedText(std::string_view utf8, std::optional<TextBoxStyle> style) {
  const Selection *selection = CurrentSelection();
  if (!selection || selection->items.size() != 1 || utf8.empty()) return false;
  const ElementRef item = selection->items.front();
  Page page = *selection->value;
  const Text *old = std::get_if<Text>(&page.layers[item.layer].elements[item.index]->value);
  if (!old) return false;
  Text changed = *old;
  changed.lines = TextLines(utf8);
  if (style) { changed.width = style->width; changed.rtl = style->rtl; }
  page.layers[item.layer].elements = page.layers[item.layer].elements.set(
      item.index, immer::box<Element>(Element{std::move(changed)}));
  Document next = document();
  next.pages = next.pages.set(selection->page, immer::box<Page>(std::move(page)));
  PushSelection(std::move(next), selection->page, selection->items);
  return true;
}

std::optional<SelectionOverlay> Editor::Overlay() {
  double scale = ViewScale();
  if (select_) {
    // An insert-space drag shows the moved ink and no frame; a ruled erase
    // drag shows the page without the ink it has taken.
    if (select_->space || select_->kind == INK_SELECTOR_RULED_ERASE) return std::nullopt;
    SelectionOverlay overlay{.page = select_->page, .view_scale = scale};
    if (select_->kind == INK_SELECTOR_LASSO) {
      overlay.lasso = select_->lasso.points();
    } else if (select_->ruled) {
      if (select_->ruled->range) {
        overlay.lasso = RuledOutline(*select_->ruled->range, document().pages[select_->page]->width);
      }
    } else if (select_->kind == INK_SELECTOR_OVAL) {
      overlay.lasso = OvalPoints(select_->start, select_->last);
    } else {
      overlay.band = Rect{select_->start.x, select_->start.y, select_->last.x, select_->last.y};
    }
    return overlay;
  }
  const Selection *selection = CurrentSelection();
  if (!selection) return std::nullopt;
  SelectionOverlay overlay{.page = selection->page,
                           .frame = selection->rect,
                           .rotate_handle = RotateHandle(selection->rect, scale),
                           .handles = !transform_,
                           .view_scale = scale};
  if (transform_) {
    overlay.live = transform_->live;
    overlay.floating = Selected(*selection);
  }
  return overlay;
}

bool Editor::TakeOverlayChanged() {
  bool changed = overlay_version_ != overlay_taken_;
  overlay_taken_ = overlay_version_;
  return changed;
}

}  // namespace ink_engine
