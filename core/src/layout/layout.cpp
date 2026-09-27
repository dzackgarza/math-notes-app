#include "layout/layout.h"

#include <algorithm>

namespace ink_engine {

std::vector<PagePlacement> LayoutPages(const Document &document) {
  double content_width = 0;
  for (const auto &page : document.pages) {
    if (!page->unlisted) content_width = std::max(content_width, page->width);
  }
  std::vector<PagePlacement> layout;
  double y = 0;
  for (size_t i = 0; i < document.pages.size(); ++i) {
    const Page &page = *document.pages[i];
    if (page.unlisted) continue;
    layout.push_back({i, (content_width - page.width) / 2, y, page.width, page.height});
    y += page.height + kPageGap;
  }
  return layout;
}

const PagePlacement *PageAt(const std::vector<PagePlacement> &layout, double y) {
  if (layout.empty()) return nullptr;
  if (y < layout.front().y) return &layout.front();
  for (const PagePlacement &p : layout) {
    if (y < p.y) return nullptr;
    if (y < p.y + p.height) return &p;
  }
  return &layout.back();
}

}  // namespace ink_engine
