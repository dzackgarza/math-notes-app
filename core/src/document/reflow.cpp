// Adapted from Write 401b65d5 selection.cpp:452-585 and
// scribblearea.cpp:1609-1640,1833-1890 (AGPL-3.0).
// Fixed-page overflow is the Math Notes rule in the v1 ruled-editing decision.
#include "document/reflow.h"

#include <algorithm>
#include <cmath>
#include <limits>
#include <stdexcept>
#include <tuple>

#include "geometry/affine.h"
#include "selection/ruled.h"

namespace ink_engine {
namespace {
struct Item {
  size_t page, layer, index, target;
  Element element;
  Rect bounds;
  double dx = 0, dy = 0;
  int line = 0;
  double within_line = 0;
};
bool Editable(const Document &doc, const std::string &id) {
  auto layer = std::find_if(doc.notebook.layers.begin(), doc.notebook.layers.end(),
                            [&](const Layer &value) { return value.id == id; });
  return layer == doc.notebook.layers.end() || (!layer->hidden && !layer->locked);
}
int LineCount(const Page &page, const RuledGrid &grid) {
  return std::max(1, static_cast<int>(std::floor((page.height - grid.offset) / grid.spacing)));
}
}  // namespace

Document InsertSpace(Document document, size_t first_page, Point start, Point end, SpaceMode mode,
                     IdGenerator &ids, const std::optional<Page> &template_page) {
  if (first_page >= ListedPageCount(document)) throw std::out_of_range("page index out of range");
  const Document original = document;
  const auto first_grid = WorkingGrid(*document.pages[first_page], start.y);
  const double dx = end.x - start.x, dy = end.y - start.y;
  if ((mode == SpaceMode::kVertical && dy == 0) || (mode == SpaceMode::kHorizontal && dx == 0))
    return document;
  const int dline = first_grid.Line(end.y) - first_grid.Line(start.y);
  std::vector<Item> items;
  int line_base = 0;
  for (size_t p = first_page; p < ListedPageCount(original); ++p) {
    const auto &page = *original.pages[p];
    if (page.error) throw std::runtime_error("repair error pages before inserting space");
    const auto grid = p == first_page
                          ? first_grid
                          : WorkingGrid(page, first_grid.offset + first_grid.spacing / 2);
    Page working = page;
    working.background.ruling = Ruling::kLined;
    working.background.y_ruling = grid.spacing;
    working.background.y_offset = grid.offset;
    for (auto &layer : working.layers)
      if (!Editable(original, layer.layer_id)) layer.elements = {};
    const auto range = MakeRuledRange(working, start, {page.width, page.height});
    for (size_t l = 0; l < page.layers.size(); ++l) {
      if (!Editable(original, page.layers[l].layer_id)) continue;
      for (size_t i = 0; i < page.layers[l].elements.size(); ++i) {
        const auto &element = *page.layers[l].elements[i];
        const auto bounds = ElementBounds(element);
        const bool select =
            p != first_page || (mode == SpaceMode::kVertical     ? bounds.top >= start.y
                                : mode == SpaceMode::kHorizontal ? bounds.left >= start.x
                                                                 : InRuledRange(element, range));
        if (!select) continue;
        const double center = RuledCenter(element).y;
        const int line = grid.Line(center);
        items.push_back(
            {p, l, i, p, element, bounds, 0, 0, line_base + line, center - grid.Top(line)});
      }
    }
    line_base += LineCount(page, grid);
  }
  if (items.empty()) return document;
  auto appendPage = [&] {
    const size_t count = ListedPageCount(document);
    document = ink_engine::InsertPage(std::move(document), count, ids, template_page);
  };
  auto gridAt = [&](size_t p) {
    return p == first_page
               ? first_grid
               : WorkingGrid(*document.pages[p], first_grid.offset + first_grid.spacing / 2);
  };
  auto locateLine = [&](int line) {
    if (line < 0)
      throw std::invalid_argument("inserted space moves content before the first editable page");
    size_t p = first_page;
    while (true) {
      if (p == ListedPageCount(document)) appendPage();
      const int count = LineCount(*document.pages[p], gridAt(p));
      if (line < count) return std::pair<size_t, int>{p, line};
      line -= count;
      ++p;
    }
  };

  if (mode == SpaceMode::kRuled) {
    std::stable_sort(items.begin(), items.end(), [](const Item &a, const Item &b) {
      return std::tie(a.line, a.bounds.left) < std::tie(b.line, b.bounds.left);
    });
    const int first_line = items.front().line;
    for (auto &item : items) {
      if (first_line == first_grid.Line(start.y) && item.line == first_line &&
          start.x > original.pages[first_page]->background.margin_left)
        item.dx = dx;
      item.line += dline;
    }
    const double gap = .3 * first_grid.spacing;  // Write minWordSep default.
    auto left = [](const Item &item) { return item.bounds.left + item.dx; };
    auto right = [](const Item &item) { return item.bounds.right + item.dx; };
    size_t current = 0, wordbreak = 0;
    int line = items.front().line;
    double current_right = 0;
    while (current < items.size()) {
      const auto [p, local_line] = locateLine(line);
      const auto &page = *document.pages[p];
      Page visible = page;
      for (auto &layer : visible.layers)
        if (!Editable(document, layer.layer_id)) layer.elements = {};
      auto range =
          MakeRuledRange(visible, {start.x, gridAt(p).Top(local_line) + gridAt(p).spacing / 2},
                         {page.width, page.height});
      const double margin = std::max(page.background.margin_left, range.Left(local_line + 1));
      const double edge = std::min(page.width, range.Right(local_line)) - .5 * gap;
      while (current < items.size() && items[current].line == line) {
        current_right = std::max(current_right, right(items[current]));
        if (current_right >= edge) break;
        ++current;
        if (current == items.size() || items[current].line != line) break;
        if (left(items[current]) - current_right >= gap) wordbreak = current;
      }
      if (current == items.size() || items[current].line != line) break;
      if (wordbreak == items.size())
        throw std::invalid_argument("a word is wider than its writable line");
      size_t next = current;
      while (next < items.size() && items[next].line == line) ++next;
      double destination = margin + gap;
      if (next < items.size() && items[next].line == line + 1) destination = left(items[next]);
      const double shift = destination - left(items[wordbreak]);
      double occupied = 0;
      for (size_t i = wordbreak; i < next; ++i) {
        items[i].dx += shift;
        ++items[i].line;
        occupied = std::max(occupied, right(items[i]));
      }
      ++line;
      size_t rest = next;
      if (rest < items.size() && items[rest].line == line) {
        const double shift_next = occupied + 1.25 * gap - left(items[rest]);
        while (rest < items.size() && items[rest].line == line) items[rest++].dx += shift_next;
      } else {
        for (; rest < items.size(); ++rest) ++items[rest].line;
      }
      current = wordbreak;
      current_right = -std::numeric_limits<double>::infinity();
      wordbreak = items.size();
    }
    // Keep each line intact at a fixed page boundary. Later lines move with it.
    for (size_t i = 0; i < items.size();) {
      size_t end_line = i + 1;
      while (end_line < items.size() && items[end_line].line == items[i].line) ++end_line;
      while (true) {
        const auto [p, local] = locateLine(items[i].line);
        double top = std::numeric_limits<double>::infinity(), bottom = -top;
        for (size_t k = i; k < end_line; ++k) {
          const double shift =
              gridAt(p).Top(local) + items[k].within_line - RuledCenter(items[k].element).y;
          top = std::min(top, items[k].bounds.top + shift);
          bottom = std::max(bottom, items[k].bounds.bottom + shift);
        }
        if (bottom - top > document.pages[p]->height)
          throw std::invalid_argument("a line is taller than the destination page");
        if (top >= 0 && bottom <= document.pages[p]->height) break;
        const double base = gridAt(p).Top(local);
        const int earliest = std::max(
            0, static_cast<int>(std::ceil((base - top - gridAt(p).offset) / gridAt(p).spacing)));
        const bool fits = gridAt(p).Top(earliest) + bottom - base <= document.pages[p]->height;
        if (!fits && p >= ListedPageCount(original))
          throw std::invalid_argument("this line cannot fit on a template page");
        const int advance = fits && top < 0 ? static_cast<int>(std::ceil(-top / gridAt(p).spacing))
                                            : LineCount(*document.pages[p], gridAt(p)) - local;
        for (size_t k = i; k < items.size(); ++k) items[k].line += std::max(1, advance);
      }
      for (size_t k = i; k < end_line; ++k) {
        const auto [target, target_line] = locateLine(items[k].line);
        items[k].target = target;
        items[k].dy = gridAt(target).Top(target_line) + items[k].within_line -
                      RuledCenter(items[k].element).y;
      }
      i = end_line;
    }
  } else {
    const bool vertical = mode == SpaceMode::kVertical;
    std::vector<double> offsets{0};
    for (size_t p = first_page; p < ListedPageCount(document); ++p)
      offsets.push_back(offsets.back() +
                        (vertical ? document.pages[p]->height : document.pages[p]->width));
    std::stable_sort(items.begin(), items.end(), [&](const Item &a, const Item &b) {
      return a.page != b.page ? a.page < b.page
             : vertical       ? a.bounds.top < b.bounds.top
                              : a.bounds.left < b.bounds.left;
    });
    double extra = 0;
    for (auto &item : items) {
      double position = offsets[item.page - first_page] +
                        (vertical ? item.bounds.top + dy : item.bounds.left + dx) + extra;
      const double extent =
          vertical ? item.bounds.bottom - item.bounds.top : item.bounds.right - item.bounds.left;
      if (position < 0)
        throw std::invalid_argument("inserted space moves content before the first editable page");
      size_t target = 0;
      while (target + 1 < offsets.size() && position >= offsets[target + 1]) ++target;
      while (true) {
        if (first_page + target == ListedPageCount(document)) {
          appendPage();
          offsets.push_back(offsets.back() + (vertical
                                                  ? document.pages[first_page + target]->height
                                                  : document.pages[first_page + target]->width));
        }
        const double size = offsets[target + 1] - offsets[target];
        if (position >= offsets[target + 1]) {
          ++target;
          continue;
        }
        if (extent > size)
          throw std::invalid_argument("an object is larger than the destination page");
        if (position - offsets[target] + extent <= size) break;
        const double next = offsets[++target];
        extra += next - position;
        position = next;
      }
      item.target = first_page + target;
      if (vertical)
        item.dy = position - offsets[target] - item.bounds.top;
      else
        item.dx = position - offsets[target] - item.bounds.left;
    }
  }

  std::sort(items.begin(), items.end(), [](const Item &a, const Item &b) {
    return std::tie(a.page, a.layer, a.index) < std::tie(b.page, b.layer, b.index);
  });
  size_t cursor = 0;
  for (size_t p = first_page; p < ListedPageCount(document); ++p) {
    Page page = *document.pages[p];
    bool changed = false;
    for (size_t l = 0; l < page.layers.size(); ++l) {
      Elements elements;
      for (size_t i = 0; i < page.layers[l].elements.size(); ++i) {
        if (cursor < items.size() && std::tie(items[cursor].page, items[cursor].layer,
                                              items[cursor].index) == std::tie(p, l, i)) {
          const auto &item = items[cursor++];
          if (item.target == p)
            elements = elements.push_back(
                immer::box<Element>(Transformed(item.element, Translation(item.dx, item.dy))));
          changed = true;
        } else
          elements = elements.push_back(page.layers[l].elements[i]);
      }
      for (const auto &item : items)
        if (item.target == p && item.page != p &&
            original.pages[item.page]->layers[item.layer].layer_id == page.layers[l].layer_id) {
          elements = elements.push_back(
              immer::box<Element>(Transformed(item.element, Translation(item.dx, item.dy))));
          changed = true;
        }
      page.layers[l].elements = std::move(elements);
    }
    if (changed) document.pages = document.pages.set(p, immer::box<Page>(std::move(page)));
  }
  return document;
}
}  // namespace ink_engine
