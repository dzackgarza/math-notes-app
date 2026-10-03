// Insert space: Write's MODE_INSSPACEVERT, MODE_INSSPACEHORZ and
// MODE_INSSPACERULED tools (Stylus Labs Write 401b65d5, AGPL-3.0;
// scribblearea.cpp:1609-1640 press, 1833-1885 move, 2163-2193 release) with
// Selection::insertSpace and Selection::reflowStrokes (selection.cpp:452-570).
//
// The pen-down selects the ink that moves: below the pen (vertical), right
// of it (horizontal), or after it in reading order (ruled). Each pen position
// then gives a document: the selected ink moved by the drag from the pen-down.
// In ruled mode a pen-down right of the margin on a line with ink after it
// moves the rest of that line sideways and reflows words that pass the end of
// a line onto the next lines; any other ruled drag moves whole lines. A ruled
// drag up or to the left deletes the ink it passes over.
//
// Write grows its page under the ink. A Math Notes page has a fixed size
// (docs/ARCHITECTURE.md, "Engine integration"), which adds these rules:
// - The pen position is limited to the page, and ink pushed sideways stops
//   at the right edge.
// - Ink pushed past the bottom of the page goes to the next page, at the
//   same distance below that page's first line (ruled) or top edge. The ink
//   of that page moves down by the depth that the arriving ink takes, and its
//   last lines go to the page after it in the same way. A page is added after
//   the last page when needed. No other page changes.
#pragma once
#include "document/pages.h"
#include "selection/ruled.h"

namespace ink_engine {
enum class SpaceMode { kVertical, kHorizontal, kRuled };

// One drag of the tool, from the pen-down.
struct SpaceGesture {
  // An element that moves, where the last pen position put it.
  struct Item {
    size_t layer, index;
    Rect bounds;
    int line = 0;  // ruled: the line of its center
    double dx = 0, dy = 0;
    immer::box<Element> placed;
  };
  SpaceMode mode = SpaceMode::kRuled;
  size_t page = 0;
  Point start;
  // Write tempSelection. Ruled: by line, then from the left
  // (Selection::sortRuled).
  std::vector<Item> items;
  RuledGrid grid{};
  GroupedCenters grouped;
  RuledStops stops;  // the columns at the pen-down
  // Write insertSpaceX: the drag moves the rest of the first line sideways.
  bool insert_x = false;
  // The columns where the pen first went to another line: Write's second
  // selector, for the ink that a drag up or left deletes.
  RuledStops erase_stops;
};

SpaceGesture BeginInsertSpace(const Document &document, size_t page, Point start, SpaceMode mode);

// `document`, which the gesture began on, with the pen at `at`. All changed
// pages form one value for the editor's history.
Document InsertSpace(const Document &document, SpaceGesture &gesture, Point at, IdGenerator &ids,
                     const std::optional<Page> &template_page);
}  // namespace ink_engine
