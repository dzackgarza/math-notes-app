// Adapted from Stylus Labs Write 401b65d5, selection.cpp:819-1090 and
// page.cpp:79-109 (AGPL-3.0). Coordinates here are points, not Write units.
#pragma once
#include "selection/selection.h"

namespace ink_engine {
struct RuledGrid {
  double spacing, offset;
  int Line(double y) const;
  double Top(int line) const;
};
RuledGrid WorkingGrid(const Page &page, double gesture_y);
Point RuledCenter(const Element &element);
struct RuledRange {
  RuledGrid grid;
  int first, last;
  double x0, x1;
  std::vector<double> left, right;
  double Left(int line) const;
  double Right(int line) const;
};
RuledRange MakeRuledRange(const Page &page, Point start, Point end, bool columns = true);
bool InRuledRange(const Element &element, const RuledRange &range, bool overlap = false);
}  // namespace ink_engine
