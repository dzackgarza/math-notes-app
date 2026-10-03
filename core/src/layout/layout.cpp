#include "layout/layout.h"

#include <algorithm>
#include <span>

namespace ink_engine {

std::vector<PagePlacement> LayoutPages(const Document &document, PageArrangement arrangement) {
  std::vector<std::vector<size_t>> rows;
  for (size_t i = 0; i < document.pages.size(); ++i) {
    if (document.pages[i]->unlisted) continue;
    bool fresh = rows.empty() || arrangement == PageArrangement::kVertical ||
                 (arrangement == PageArrangement::kTwoPage && rows.back().size() == 2);
    if (fresh) rows.emplace_back();
    rows.back().push_back(i);
  }
  auto row_width = [&](const std::vector<size_t> &row) {
    double width = kPageGap * double(row.size() - 1);
    for (size_t i : row) width += document.pages[i]->width;
    return width;
  };
  double content_width = 0;
  for (const auto &row : rows) content_width = std::max(content_width, row_width(row));
  std::vector<PagePlacement> layout;
  double y = 0;
  for (const auto &row : rows) {
    double x = (content_width - row_width(row)) / 2, height = 0;
    for (size_t i : row) {
      const Page &page = *document.pages[i];
      layout.push_back({i, x, y, page.width, page.height});
      x += page.width + kPageGap;
      height = std::max(height, page.height);
    }
    y += height + kPageGap;
  }
  return layout;
}

const PagePlacement *PageAt(const std::vector<PagePlacement> &layout, Point at) {
  if (layout.empty()) return nullptr;
  // The row of pages that share a top edge and whose band of y holds at.y.
  std::span<const PagePlacement> row;
  for (size_t begin = 0; begin < layout.size();) {
    size_t end = begin;
    double bottom = layout[begin].y;
    while (end < layout.size() && layout[end].y == layout[begin].y) {
      bottom = std::max(bottom, layout[end].y + layout[end].height);
      ++end;
    }
    row = std::span(layout).subspan(begin, end - begin);
    if (at.y < layout[begin].y) {
      if (begin > 0) return nullptr;
      break;
    }
    if (at.y < bottom) break;
    begin = end;
  }
  if (at.x < row.front().x) return &row.front();
  for (const PagePlacement &p : row) {
    if (at.x < p.x) return nullptr;
    if (at.x < p.x + p.width) return &p;
  }
  return &row.back();
}

}  // namespace ink_engine
