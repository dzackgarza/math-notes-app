#include "document/reflow.h"

#include <algorithm>
#include <cmath>
#include <limits>
#include <map>
#include <set>
#include <stdexcept>
#include <tuple>

#include "geometry/affine.h"

namespace ink_engine {
namespace {
constexpr double kInfinity = std::numeric_limits<double>::infinity();
// Write minWordSep (scribblearea.cpp:47): the least gap between two words,
// in lines.
constexpr double kWordGap = 0.3;
// Write selects to MAX_LINE_NUM: all lines after the pen-down.
constexpr int kLastLine = 1 << 20;

using Place = std::pair<size_t, size_t>;  // an element's layer and index on its page

struct Shift {
  double dx = 0, dy = 0;
  int lines = 0;  // ruled: dy in lines
};

// Ink that leaves the bottom of a page. Its y is measured from the first
// line (ruled) or the top edge of the next page, and `line` counts from that
// first line.
struct Carried {
  std::string layer_id;
  Element element;
  int line = 0;
};

bool Editable(const Document &doc, const std::string &id) {
  auto layer = std::find_if(doc.notebook.layers.begin(), doc.notebook.layers.end(),
                            [&](const Layer &value) { return value.id == id; });
  return layer == doc.notebook.layers.end() || (!layer->hidden && !layer->locked);
}

// The page with only the ink that the tool can change.
Page EditablePage(const Document &document, size_t index) {
  Page page = *document.pages[index];
  for (auto &layer : page.layers)
    if (!Editable(document, layer.layer_id)) layer.elements = {};
  return page;
}

// The first line that does not end on the page.
int BottomLine(const Page &page, const RuledGrid &grid) {
  return std::max(1, static_cast<int>(std::floor((page.height - grid.offset) / grid.spacing)));
}

// Write Selection::reflowStrokes (selection.cpp:482-570): the rest of the
// first line moves by `dx` and all lines by `dline`; then each line gives the
// words that pass its right limit to the next line.
std::vector<Shift> Reflow(const SpaceGesture &g, const Page &page, double dx, int dline) {
  const auto &items = g.items;
  const size_t end = items.size();
  std::vector<Shift> shifts(end);
  for (size_t i = 0; i < end; ++i) {
    shifts[i].lines = dline;
    if (items[i].line == items.front().line) shifts[i].dx = dx;
  }
  auto line = [&](size_t i) { return items[i].line + shifts[i].lines; };
  auto left = [&](size_t i) { return items[i].bounds.left + shifts[i].dx; };
  auto right = [&](size_t i) { return items[i].bounds.right + shifts[i].dx; };

  const double gap = kWordGap * g.grid.spacing;
  const double margin = page.background.margin_left;
  size_t curr = 0, wordbreak = 0;
  double curr_right = 0;
  int currline = line(0);
  double line_left = margin, line_right = page.width - 0.5 * gap;
  while (true) {
    if (currline >= 0 && static_cast<size_t>(currline) + 1 < g.stops.left.size()) {
      line_left = std::max(margin, g.stops.left[currline + 1]);
      line_right = g.stops.right[currline] - 0.5 * gap;
    }
    // Step 1: the last word break before the right limit.
    while (true) {
      curr_right = std::max(curr_right, right(curr));
      if (curr_right >= line_right) break;
      ++curr;
      // Nothing passes the limit on this line: the reflow is complete.
      if (curr == end || line(curr) != currline) return shifts;
      if (left(curr) - curr_right >= gap) wordbreak = curr;
    }
    // One word fills the line: it stays.
    if (wordbreak == end) return shifts;
    // Step 1.5: the moved words start where the next line starts, or at the
    // left limit when the next line is empty.
    double target = line_left + gap;
    while (++curr != end) {
      if (line(curr) == currline) continue;
      if (line(curr) == currline + 1) target = left(curr);
      break;
    }
    // Step 2: the words from the break go down one line.
    const double move = target - left(wordbreak);
    double next_dx = 0;
    bool blank = false;
    for (curr = wordbreak; curr != end && line(curr) == currline; ++curr) {
      shifts[curr].dx += move;
      ++shifts[curr].lines;
      next_dx = std::max(next_dx, right(curr));
      blank = true;
    }
    // Step 3: the ink of the next line moves right, after the moved words.
    ++currline;
    for (; curr != end && line(curr) == currline; ++curr) {
      if (blank) next_dx += 1.25 * gap - left(curr);
      shifts[curr].dx += next_dx;
      blank = false;
    }
    // The words went to an empty line: a new empty line follows it.
    if (blank)
      for (size_t rest = curr; rest != end; ++rest) ++shifts[rest].lines;
    curr = wordbreak;
    curr_right = -kInfinity;
    wordbreak = end;
  }
}

// Write scribblearea.cpp:1876-1881: a ruled drag up or to the left selects
// the ink between the pen and the pen-down that does not move; the release
// deletes it.
std::set<Place> Swept(const Document &document, SpaceGesture &g, Point at) {
  const Page page = EditablePage(document, g.page);
  if (g.erase_stops.left.empty() && g.grid.Line(at.y) != g.grid.Line(g.start.y))
    g.erase_stops = FindStops(page, g.grid, at);
  const RuledRange range = MakeRuledRange(g.grid, at, g.start, g.erase_stops);
  std::set<Place> moving, swept;
  for (const auto &item : g.items) moving.insert({item.layer, item.index});
  for (size_t l = 0; l < page.layers.size(); ++l) {
    const auto &elements = page.layers[l].elements;
    for (size_t i = 0; i < elements.size(); ++i)
      if (!moving.contains({l, i}) && InRuledRange(*elements[i], range, g.grouped))
        swept.insert({l, i});
  }
  return swept;
}

// Puts the ink that left the gesture's page on the pages after it.
Document Carry(Document document, const SpaceGesture &g, std::vector<Carried> carried,
               IdGenerator &ids, const std::optional<Page> &template_page) {
  const bool ruled = g.mode == SpaceMode::kRuled;
  for (size_t p = g.page + 1; !carried.empty(); ++p) {
    if (p == ListedPageCount(document) || document.pages[p]->error)
      document = InsertPage(std::move(document), p, ids, template_page);
    Page page = *document.pages[p];
    // A blank page continues the lines of the gesture's page.
    const RuledGrid grid = WorkingGrid(page, g.grid.offset + g.grid.spacing / 2);
    const int bottom = BottomLine(page, grid);
    const double edge = ruled ? grid.Top(bottom) : page.height;

    // The arriving ink goes lower when its top is above the page. `depth` is
    // the room that it takes from the ink of this page.
    double top = 0, low = 0;
    int last = 0;
    for (const Carried &c : carried) {
      const Rect bounds = ElementBounds(c.element);
      last = std::max(last, c.line);
      low = std::max(low, bounds.bottom);
      // Ruled ink for a later page does not lower the ink for this one.
      if (!ruled || c.line < bottom) top = std::min(top, bounds.top + (ruled ? grid.Top(0) : 0));
    }
    const int raise = ruled ? static_cast<int>(std::ceil(-top / grid.spacing)) : 0;
    const double arrive = ruled ? grid.Top(0) + raise * grid.spacing : -top;
    const int lines = last + raise + 1;
    const double depth = ruled ? lines * grid.spacing : low + arrive;

    const GroupedCenters grouped = ruled ? GroupStrokes(page, grid.spacing) : GroupedCenters{};
    std::vector<Carried> onward;
    size_t placed = 0;
    for (LayerContent &layer : page.layers) {
      if (!Editable(document, layer.layer_id)) continue;
      Elements elements;
      auto put = [&](const Element &element, double dy, bool leaves, int line) {
        if (leaves)
          onward.push_back({layer.layer_id, Transformed(element, Translation(0, dy - edge)), line});
        else
          elements = std::move(elements).push_back(
              immer::box<Element>(Transformed(element, Translation(0, dy))));
      };
      for (const auto &element : layer.elements) {
        if (ruled) {
          const int line = grid.Line(RuledCenter(*element, grouped).y) + lines;
          put(*element, depth, line >= bottom, line - bottom);
        } else {
          const Rect bounds = ElementBounds(*element);
          put(*element, depth, bounds.bottom + depth > page.height && bounds.top + depth > 0, 0);
        }
      }
      for (const Carried &c : carried) {
        if (c.layer_id != layer.layer_id) continue;
        ++placed;
        if (ruled) {
          const bool leaves = c.line >= bottom;
          put(c.element, leaves ? grid.Top(0) : arrive, leaves, c.line - bottom);
        } else {
          // An element that starts at the top of a page stays on it.
          const Rect bounds = ElementBounds(c.element);
          put(c.element, arrive, bounds.bottom + arrive > page.height && bounds.top + arrive > 0, 0);
        }
      }
      layer.elements = std::move(elements);
    }
    if (placed != carried.size())
      throw std::logic_error("page " + page.id + " does not have the layer of the ink it receives");
    document.pages = document.pages.set(p, immer::box<Page>(std::move(page)));
    carried = std::move(onward);
  }
  return document;
}
}  // namespace

SpaceGesture BeginInsertSpace(const Document &document, size_t index, Point start, SpaceMode mode) {
  if (index >= ListedPageCount(document)) throw std::out_of_range("page index out of range");
  const Page page = EditablePage(document, index);
  SpaceGesture g{.mode = mode, .page = index, .start = start, .grid = WorkingGrid(page, start.y)};
  const bool ruled = mode == SpaceMode::kRuled;
  RuledRange range{};
  if (ruled) {
    g.grouped = GroupStrokes(page, g.grid.spacing);
    g.stops = FindStops(page, g.grid, start);
    range = MakeRuledRange(g.grid, start, {kInfinity, g.grid.Top(kLastLine)}, g.stops);
  }
  for (size_t l = 0; l < page.layers.size(); ++l) {
    const auto &elements = page.layers[l].elements;
    for (size_t i = 0; i < elements.size(); ++i) {
      const Rect bounds = ElementBounds(*elements[i]);
      if (IsEmpty(bounds)) continue;
      // Write RectSelector::selectRect: the ink with its bounds past the pen.
      const bool moves = mode == SpaceMode::kVertical     ? bounds.top >= start.y
                         : mode == SpaceMode::kHorizontal ? bounds.left >= start.x
                                                          : InRuledRange(*elements[i], range, g.grouped);
      if (!moves) continue;
      const int line = ruled ? g.grid.Line(RuledCenter(*elements[i], g.grouped).y) : 0;
      g.items.push_back({l, i, bounds, line, 0, 0, elements[i]});
    }
  }
  if (!ruled) return g;
  std::stable_sort(g.items.begin(), g.items.end(), [](const auto &a, const auto &b) {
    return std::tie(a.line, a.bounds.left) < std::tie(b.line, b.bounds.left);
  });
  g.insert_x = start.x > page.background.margin_left && !g.items.empty() &&
               g.items.front().line == g.grid.Line(start.y);
  return g;
}

Document InsertSpace(const Document &document, SpaceGesture &g, Point at, IdGenerator &ids,
                     const std::optional<Page> &template_page) {
  const Page &page = *document.pages[g.page];
  at = {std::clamp(at.x, 0.0, page.width), std::clamp(at.y, 0.0, page.height)};
  const bool ruled = g.mode == SpaceMode::kRuled;
  std::vector<Shift> shifts(g.items.size());
  std::set<Place> erased;
  if (g.mode == SpaceMode::kVertical) {
    for (Shift &shift : shifts) shift.dy = at.y - g.start.y;
  } else if (g.mode == SpaceMode::kHorizontal) {
    double room = kInfinity;
    for (const auto &item : g.items) room = std::min(room, page.width - item.bounds.right);
    for (Shift &shift : shifts) shift.dx = std::min(at.x - g.start.x, std::max(0.0, room));
  } else {
    const int start_line = g.grid.Line(g.start.y), line = g.grid.Line(at.y);
    if (!g.items.empty()) {
      // Write makes no change when the drag puts the first line above the
      // page (selection.cpp:485-486). Here the first line stops at the top.
      const int dline = std::max(line - start_line, g.grid.Line(0) - g.items.front().line);
      // Write scribblearea.cpp:1853-1857.
      if (g.insert_x) {
        shifts = Reflow(g, page, at.x - g.start.x, dline);
      } else {
        for (Shift &shift : shifts) shift.lines = dline;
      }
      for (Shift &shift : shifts) shift.dy = shift.lines * g.grid.spacing;
    }
    if (line < start_line || (line == start_line && at.x < g.start.x))
      erased = Swept(document, g, at);
  }

  std::map<Place, size_t> moving;
  for (size_t k = 0; k < g.items.size(); ++k) moving[{g.items[k].layer, g.items[k].index}] = k;
  const int bottom = BottomLine(page, g.grid);
  Page next = page;
  std::vector<Carried> carried;
  for (size_t l = 0; l < page.layers.size(); ++l) {
    Elements elements;
    for (size_t i = 0; i < page.layers[l].elements.size(); ++i) {
      if (erased.contains({l, i})) continue;
      const auto &original = page.layers[l].elements[i];
      const auto found = moving.find({l, i});
      if (found == moving.end()) {
        elements = std::move(elements).push_back(original);
        continue;
      }
      SpaceGesture::Item &item = g.items[found->second];
      const Shift &shift = shifts[found->second];
      // An element with the same shift as before keeps its value, and the
      // renderer its drawing.
      if (shift.dx != item.dx || shift.dy != item.dy) {
        item.dx = shift.dx;
        item.dy = shift.dy;
        item.placed = shift.dx == 0 && shift.dy == 0
                          ? original
                          : immer::box<Element>(
                                Transformed(*original, Translation(shift.dx, shift.dy)));
      }
      const int line = item.line + shift.lines;
      if (ruled && shift.lines > 0 && line >= bottom) {
        carried.push_back({page.layers[l].layer_id,
                           Transformed(*item.placed, Translation(0, -g.grid.Top(bottom))),
                           line - bottom});
      } else if (g.mode == SpaceMode::kVertical && shift.dy > 0 &&
                 item.bounds.bottom + shift.dy > page.height) {
        carried.push_back(
            {page.layers[l].layer_id, Transformed(*item.placed, Translation(0, -page.height))});
      } else {
        elements = std::move(elements).push_back(item.placed);
      }
    }
    next.layers[l].elements = std::move(elements);
  }
  Document result = document;
  result.pages = result.pages.set(g.page, immer::box<Page>(std::move(next)));
  return Carry(std::move(result), g, std::move(carried), ids, template_page);
}
}  // namespace ink_engine
