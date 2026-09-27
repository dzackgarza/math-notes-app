#include "selection/ruled.h"

#include <algorithm>
#include <cmath>
#include <limits>

#include "geometry/affine.h"

namespace ink_engine {
int RuledGrid::Line(double y) const { return static_cast<int>(std::floor((y - offset) / spacing)); }
double RuledGrid::Top(int line) const { return offset + spacing * line; }
RuledGrid WorkingGrid(const Page &page, double y) {
  if (page.background.ruling != Ruling::kBlank && page.background.y_ruling > 0)
    return {page.background.y_ruling, page.background.y_offset};
  constexpr double spacing = 19.2;  // Write's 40 units at 0.48 pt per unit.
  return {spacing, std::fmod(y - spacing / 2, spacing)};
}
Point RuledCenter(const Element &element) {
  const auto bounds = ElementBounds(element);
  Point center{(bounds.left + bounds.right) / 2, (bounds.top + bounds.bottom) / 2};
  if (const auto *stroke = std::get_if<Stroke>(&element.value);
      stroke && !stroke->samples.empty()) {
    // Write StrokeBuilder::calcCom weights mean input, first input and ink top.
    double sum = 0;
    for (const auto &sample : stroke->samples)
      sum += Apply(stroke->transform, {sample.x, sample.y}).y;
    const auto &first = stroke->samples.front();
    center.y = (sum / stroke->samples.size() + Apply(stroke->transform, {first.x, first.y}).y +
                bounds.top) /
               3;
  }
  return center;
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
namespace {
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

RuledRange MakeRuledRange(const Page &page, Point start, Point end, bool columns) {
  const auto grid = WorkingGrid(page, start.y);
  const int a = grid.Line(start.y), b = grid.Line(end.y);
  RuledRange range{grid, a, b, start.x, end.x, {}, {}};
  if (columns && a != b && start.x >= page.background.margin_left) {
    const int count = std::max(1, grid.Line(page.height) + 1);
    range.left.assign(count, 0);
    range.right.assign(count, page.width);
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
            if (p.x > start.x)
              range.right[line] = std::min(range.right[line], p.x);
            else if (p.x < start.x)
              range.left[line] = std::max(range.left[line], p.x);
          }
        } else
          for (int line = first; line <= last; ++line) {
            if (bounds.left > start.x)
              range.right[line] = std::min(range.right[line], bounds.left);
            else if (bounds.right < start.x)
              range.left[line] = std::max(range.left[line], bounds.right);
          }
      }
    bool clear = false;
    for (int line = std::max(0, a); line < count; ++line) {
      if (clear) {
        range.left[line] = 0;
        range.right[line] = page.width;
      } else if (range.left[line] == 0 && range.right[line] == page.width)
        clear = true;
    }
  }
  if (a > b || (a == b && start.x > end.x)) {
    std::swap(range.first, range.last);
    std::swap(range.x0, range.x1);
  }
  return range;
}

bool InRuledRange(const Element &element, const RuledRange &range, bool overlap) {
  auto group = [&](const Elements &children, const Transform &transform) {
    auto hit = [&](const auto &child) {
      return InRuledRange(Transformed(*child, transform), range, overlap);
    };
    return overlap ? std::any_of(children.begin(), children.end(), hit)
                   : std::all_of(children.begin(), children.end(), hit);
  };
  if (const auto *bookmark = std::get_if<Bookmark>(&element.value))
    return group(bookmark->children, {});
  if (const auto *link = std::get_if<Link>(&element.value)) return group(link->children, {});
  if (const auto *figure = std::get_if<Figure>(&element.value); figure && !figure->view)
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
      const int line = grid.Line(RuledCenter(element).y);
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
