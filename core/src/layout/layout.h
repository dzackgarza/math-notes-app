// Page layout in the scroll view (docs/specs/tablet-ui.md, "Pages in the
// editor"). Listed pages sit in rows with a small desk gap between them: one
// page per row stacked vertically, one row of all pages side by side, or two
// pages per row. Content coordinates are pt, origin at the top left of the
// laid-out pages' extent.
#pragma once

#include <vector>

#include "document/document.h"

namespace ink_engine {

inline constexpr double kPageGap = 6;  // pt, between listed pages only

// The View menu's page layouts.
enum class PageArrangement { kVertical = 0, kHorizontal = 1, kTwoPage = 2 };

struct PagePlacement {
  size_t page = 0;  // index in Document::pages
  double x = 0, y = 0, width = 0, height = 0;
  bool operator==(const PagePlacement &) const = default;
};

// Listed pages in order; unlisted pages are not laid out. Each row is
// centered on the widest row, and its pages share the row's top edge.
std::vector<PagePlacement> LayoutPages(const Document &document, PageArrangement arrangement);

// The placement a pen-down at content point `at` draws on: the row whose
// band of y holds `at`, then the page of that row whose band of x holds it;
// no page in a gap; the first or last row or page beyond the ends.
const PagePlacement *PageAt(const std::vector<PagePlacement> &layout, Point at);

}  // namespace ink_engine
