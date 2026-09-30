#include "selection/ruled.h"

#include <algorithm>
#include <cmath>
#include <limits>

#include "absl/time/time.h"
#include "geometry/affine.h"

namespace ink_engine {
namespace {
// A stroke's box in its own coordinates: its samples, widened by half its
// size (Write SvgPainter::_bounds, usvg/svgpainter.cpp:626-646).
Rect DrawnBox(const Stroke &stroke) {
  const Sample &first = stroke.samples.front();
  Rect box{first.x, first.y, first.x, first.y};
  for (const Sample &s : stroke.samples) box = Union(box, {s.x, s.y, s.x, s.y});
  const double half = stroke.size / 2;
  return {box.left - half, box.top - half, box.right + half, box.bottom + half};
}

struct Drawn {
  const Stroke *stroke;
  double end;  // ms, UTC
  Rect box;
};

// The strokes of a layer, those in groups included. A stroke with no samples
// or no readable time was not drawn in sequence and is in no group.
void CollectDrawn(const Elements &elements, std::vector<Drawn> &drawn) {
  for (const auto &element : elements) {
    if (const auto *stroke = std::get_if<Stroke>(&element->value)) {
      absl::Time start;
      if (stroke->samples.empty() ||
          !absl::ParseTime(absl::RFC3339_full, stroke->time, &start, nullptr))
        continue;
      drawn.push_back({stroke, double(absl::ToUnixMillis(start)) + stroke->samples.back().t,
                       DrawnBox(*stroke)});
    } else if (const auto *bookmark = std::get_if<Bookmark>(&element->value)) {
      CollectDrawn(bookmark->children, drawn);
    } else if (const auto *link = std::get_if<Link>(&element->value)) {
      CollectDrawn(link->children, drawn);
    } else if (const auto *figure = std::get_if<Figure>(&element->value)) {
      CollectDrawn(figure->children, drawn);
    }
  }
}

std::vector<Point> PathPoints(const Stroke &stroke, double step) {
  std::vector<Point> points;
  for (const auto &path : stroke.outline) {
    if (path.empty()) continue;
    for (size_t i = 0; i < path.size(); ++i) {
      Point a = Apply(stroke.transform, path[i]);
      Point b = Apply(stroke.transform, path[(i + 1) % path.size()]);
      const int n =
          std::max(1, static_cast<int>(std::ceil(std::hypot(b.x - a.x, b.y - a.y) / step)));
      for (int j = 0; j < n; ++j)
        points.push_back({a.x + (b.x - a.x) * j / n, a.y + (b.y - a.y) * j / n});
    }
  }
  return points;
}
}  // namespace

int RuledGrid::Line(double y) const { return static_cast<int>(std::floor((y - offset) / spacing)); }
double RuledGrid::Top(int line) const { return offset + spacing * line; }
RuledGrid WorkingGrid(const Page &page, double y) {
  if (page.background.ruling != Ruling::kBlank && page.background.y_ruling > 0)
    return {page.background.y_ruling,
            std::fmod(page.background.y_offset, page.background.y_ruling)};
  constexpr double spacing = 19.2;  // Write's 40 units at 0.48 pt per unit.
  return {spacing, std::fmod(y - spacing / 2, spacing)};
}

// Write groups strokes while the pen draws them, and ends a group at each
// other gesture. The stroke times give the same sequence.
GroupedCenters GroupStrokes(const Page &page, double spacing) {
  GroupedCenters grouped;
  for (const LayerContent &layer : page.layers) {
    std::vector<Drawn> drawn;
    CollectDrawn(layer.elements, drawn);
    std::stable_sort(drawn.begin(), drawn.end(),
                     [](const Drawn &a, const Drawn &b) { return a.end < b.end; });
    std::vector<const Stroke *> recent;
    double sum = 0;
    for (size_t i = 0; i < drawn.size(); ++i) {
      const Drawn &a = drawn[i];
      recent.push_back(a.stroke);
      sum += (a.box.top + a.box.bottom) / 2;
      const double center = sum / recent.size();
      const bool tight = recent.size() > 3;
      const double top = center - (tight ? 1.0 : 1.25) * spacing;
      const double bottom = center + (tight ? 0.8 : 1.25) * spacing;
      if (i + 1 < drawn.size()) {
        const Drawn &b = drawn[i + 1];
        if (a.end + 2500 >= b.end && a.box.right + 1.5 * spacing >= b.box.left &&
            a.box.left - 0.25 * spacing <= b.box.right && b.box.top >= top &&
            b.box.bottom <= bottom)
          continue;
      }
      if (tight)
        for (const Stroke *stroke : recent) grouped[stroke->id] = center;
      recent.clear();
      sum = 0;
    }
  }
  return grouped;
}

Point RuledCenter(const Element &element, const GroupedCenters &grouped) {
  const auto *stroke = std::get_if<Stroke>(&element.value);
  if (!stroke || stroke->samples.empty()) {
    const auto bounds = ElementBounds(element);
    return {(bounds.left + bounds.right) / 2, (bounds.top + bounds.bottom) / 2};
  }
  // Write StrokeBuilder::calcCom weights mean input, first input and ink top.
  // The center moves with the stroke (Write element.cpp:516-517).
  const Rect box = DrawnBox(*stroke);
  double y = 0;
  if (auto found = grouped.find(stroke->id); found != grouped.end()) {
    y = found->second;
  } else {
    double sum = 0;
    for (const Sample &sample : stroke->samples) sum += sample.y;
    y = (sum / stroke->samples.size() + stroke->samples.front().y + box.top) / 3;
  }
  return Apply(stroke->transform, {(box.left + box.right) / 2, y});
}

double RuledRange::Left(int line) const {
  double stop = line >= 0 && static_cast<size_t>(line) < left.size()
                    ? left[line]
                    : -std::numeric_limits<double>::infinity();
  return line == first ? std::max(x0, stop) : stop;
}
double RuledRange::Right(int line) const {
  double stop = line >= 0 && static_cast<size_t>(line) < right.size()
                    ? right[line]
                    : std::numeric_limits<double>::infinity();
  return line == last ? std::min(x1, stop) : stop;
}

RuledStops FindStops(const Page &page, const RuledGrid &grid, Point at) {
  RuledStops stops;
  if (at.x < page.background.margin_left) return stops;
  const int a = grid.Line(at.y);
  const int count = std::max(1, grid.Line(page.height) + 1);
  stops.left.assign(count, 0);
  stops.right.assign(count, page.width);
  for (const auto &layer : page.layers)
    for (const auto &element : layer.elements) {
      const auto bounds = ElementBounds(*element);
      if (bounds.bottom - bounds.top <= 2 * grid.spacing || grid.Line(bounds.top) > a ||
          grid.Line(bounds.bottom) < a)
        continue;
      int first = std::max(0, grid.Line(bounds.top + grid.spacing * .25));
      int last = std::min(count - 1, grid.Line(bounds.bottom - grid.spacing * .25));
      if (const auto *stroke = std::get_if<Stroke>(&element->value)) {
        for (const Point p : PathPoints(*stroke, grid.spacing / 8)) {
          int line = grid.Line(p.y);
          if (line < first || line > last) continue;
          if (p.x > at.x)
            stops.right[line] = std::min(stops.right[line], p.x);
          else if (p.x < at.x)
            stops.left[line] = std::max(stops.left[line], p.x);
        }
      } else
        for (int line = first; line <= last; ++line) {
          if (bounds.left > at.x)
            stops.right[line] = std::min(stops.right[line], bounds.left);
          else if (bounds.right < at.x)
            stops.left[line] = std::max(stops.left[line], bounds.right);
        }
    }
  bool clear = false;
  for (int line = std::max(0, a); line < count; ++line) {
    if (clear) {
      stops.left[line] = 0;
      stops.right[line] = page.width;
    } else if (stops.left[line] == 0 && stops.right[line] == page.width)
      clear = true;
  }
  return stops;
}

RuledRange MakeRuledRange(const RuledGrid &grid, Point start, Point end, RuledStops stops) {
  const int a = grid.Line(start.y), b = grid.Line(end.y);
  RuledRange range{grid, a, b, start.x, end.x, std::move(stops.left), std::move(stops.right)};
  if (a > b || (a == b && start.x > end.x)) {
    std::swap(range.first, range.last);
    std::swap(range.x0, range.x1);
  }
  return range;
}

RuledRange MakeRuledRange(const Page &page, Point start, Point end, bool columns) {
  const auto grid = WorkingGrid(page, start.y);
  const bool lines = grid.Line(start.y) != grid.Line(end.y);
  return MakeRuledRange(grid, start, end,
                        columns && lines ? FindStops(page, grid, start) : RuledStops{});
}

bool InRuledRange(const Element &element, const RuledRange &range, const GroupedCenters &grouped,
                  bool overlap) {
  auto group = [&](const Elements &children, const Transform &transform) {
    auto hit = [&](const auto &child) {
      return InRuledRange(Transformed(*child, transform), range, grouped, overlap);
    };
    return overlap ? std::any_of(children.begin(), children.end(), hit)
                   : std::all_of(children.begin(), children.end(), hit);
  };
  if (const auto *bookmark = std::get_if<Bookmark>(&element.value))
    return group(bookmark->children, {});
  if (const auto *link = std::get_if<Link>(&element.value)) return group(link->children, {});
  if (const auto *figure = std::get_if<Figure>(&element.value))
    return group(figure->children, figure->transform);
  const auto bounds = ElementBounds(element);
  const auto &grid = range.grid;
  const double top = grid.Top(range.first), bottom = grid.Top(range.last + 1);
  auto horizontal = [&](int line) {
    return overlap ? bounds.left < range.Right(line) && bounds.right > range.Left(line)
                   : bounds.left >= range.Left(line) && bounds.right <= range.Right(line);
  };
  if (const auto *stroke = std::get_if<Stroke>(&element.value)) {
    if (bounds.bottom - bounds.top < 1.75 * grid.spacing) {
      const int line = grid.Line(RuledCenter(element, grouped).y);
      return line >= range.first && line <= range.last && horizontal(line);
    }
    if (overlap
            ? bounds.bottom < top + .25 * grid.spacing || bounds.top > bottom - .25 * grid.spacing
            : bounds.top < top - .25 * grid.spacing || bounds.bottom > bottom + .25 * grid.spacing)
      return false;
    for (const Point p : PathPoints(*stroke, grid.spacing / 8)) {
      const int line = grid.Line(p.y);
      if (line < range.first || line > range.last) {
        if (!overlap && (p.y < top - .25 * grid.spacing || p.y > bottom + .25 * grid.spacing))
          return false;
      } else {
        const bool inside = p.x >= range.Left(line) && p.x <= range.Right(line);
        if (overlap && inside) return true;
        if (!overlap && !inside) return false;
      }
    }
    return !overlap;
  }
  if (overlap ? bounds.bottom < top || bounds.top >= bottom
              : bounds.top < top || bounds.bottom >= bottom)
    return false;
  const int a = grid.Line(bounds.top), b = grid.Line(bounds.bottom);
  if (overlap && std::holds_alternative<Image>(element.value))
    return (a >= range.first && a <= range.last && horizontal(a)) ||
           (b >= range.first && b <= range.last && horizontal(b));
  for (int line = std::max(a, range.first); line <= std::min(b, range.last); ++line) {
    if (horizontal(line) == overlap) return overlap;
  }
  return !overlap;
}
}  // namespace ink_engine
