// Adapted from Stylus Labs Write 401b65d5, selection.cpp:819-1090,
// page.cpp:79-109, strokebuilder.cpp:38-54 and scribblearea.cpp:790-839
// (AGPL-3.0). Coordinates here are points, not Write units.
#pragma once
#include <string>
#include <unordered_map>

#include "selection/selection.h"

namespace ink_engine {
struct RuledGrid {
  double spacing, offset;
  int Line(double y) const;
  double Top(int line) const;
};
// The lines of a page. Line 0 is the first line that starts on the page. A
// blank page has Write's 40-unit lines, placed so that `gesture_y` is the
// middle of a line.
RuledGrid WorkingGrid(const Page &page, double gesture_y);

// The center height that Write's stroke grouping gives each stroke of a
// word, by stroke id, in the stroke's own coordinates
// (ScribbleArea::groupStrokes). Strokes drawn one after the other, close in
// time and position, form a group; a group of more than 3 strokes has one
// center height, so that a dot or a descender stays on the line of its word.
using GroupedCenters = std::unordered_map<std::string, double>;
GroupedCenters GroupStrokes(const Page &page, double spacing);

// The point that puts an element on a line: Write Element::com.
Point RuledCenter(const Element &element, const GroupedCenters &grouped);

// Column limits of each line, from the tall strokes left and right of a
// point (Write RuledSelector::findStops, COL_NORMAL). Empty left of the
// margin: the whole line is one column there.
struct RuledStops {
  std::vector<double> left, right;
};
RuledStops FindStops(const Page &page, const RuledGrid &grid, Point at);

struct RuledRange {
  RuledGrid grid;
  int first, last;
  double x0, x1;
  std::vector<double> left, right;
  double Left(int line) const;
  double Right(int line) const;
};
// Write RuledSelector::selectRuled: from `start` to `end` in reading order.
RuledRange MakeRuledRange(const RuledGrid &grid, Point start, Point end, RuledStops stops);
// The range with the columns found at `start` when it covers several lines.
RuledRange MakeRuledRange(const Page &page, Point start, Point end, bool columns = true);
bool InRuledRange(const Element &element, const RuledRange &range, const GroupedCenters &grouped,
                  bool overlap = false);
// The closed outline of the range on a page of that width: Write
// RuledSelector::drawBG (selection.cpp:1279-1312).
std::vector<Point> RuledOutline(const RuledRange &range, double width);
}  // namespace ink_engine
