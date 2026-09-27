#pragma once

#include "selection/selection.h"

namespace ink_engine {
struct NavigationMark {
  std::string id, href;
  size_t page;
  Rect bounds;
};
// SVG groups retain their authored children. Traversal applies figure transforms.
std::vector<NavigationMark> NavigationMarks(const Document &document, bool include_hidden = false);
// Write bookmark list: a passive ruled selection from the bookmark to the line end.
Page BookmarkLine(const Page &page, const Rect &bookmark);
std::string PageLinkTarget(const Page &source, const std::string &href);
}  // namespace ink_engine
