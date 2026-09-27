// Page layout in the scroll view: listed pages stacked vertically, each
// centered on the widest one, with a small desk gap between pages
// (docs/specs/tablet-ui.md, "Pages in the editor"). Content coordinates are
// pt, origin at the top left of the widest page's column.
#pragma once

#include <vector>

#include "document/document.h"

namespace ink_engine {

inline constexpr double kPageGap = 6;  // pt, between listed pages only

struct PagePlacement {
  size_t page = 0;  // index in Document::pages
  double x = 0, y = 0, width = 0, height = 0;
  bool operator==(const PagePlacement &) const = default;
};

// Listed pages in order; unlisted pages are not laid out.
std::vector<PagePlacement> LayoutPages(const Document &document);

// The placement a pen-down at content height y draws on: the page whose
// band holds y; no page in a gap; the first or last page beyond the ends.
const PagePlacement *PageAt(const std::vector<PagePlacement> &layout, double y);

}  // namespace ink_engine
