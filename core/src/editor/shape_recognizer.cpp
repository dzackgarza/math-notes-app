#include "editor/shape_recognizer.h"

#include <algorithm>
#include <cmath>
#include <numbers>

namespace ink_engine {
namespace {

struct Point2 {
  double x, y;
};

Point2 At(const InkPenSample &sample) { return {sample.x, sample.y}; }
Point2 Sub(Point2 a, Point2 b) { return {a.x - b.x, a.y - b.y}; }
double Dot(Point2 a, Point2 b) { return a.x * b.x + a.y * b.y; }
double Cross(Point2 a, Point2 b) { return a.x * b.y - a.y * b.x; }
double Length(Point2 a) { return std::hypot(a.x, a.y); }
double Distance(Point2 a, Point2 b) { return Length(Sub(a, b)); }

struct Bounds {
  double left, top, right, bottom;
  double Width() const { return right - left; }
  double Height() const { return bottom - top; }
  double Diagonal() const { return std::hypot(Width(), Height()); }
};

Bounds Extent(const std::vector<InkPenSample> &samples) {
  Bounds result{samples.front().x, samples.front().y, samples.front().x, samples.front().y};
  for (const auto &sample : samples) {
    result.left = std::min(result.left, sample.x);
    result.top = std::min(result.top, sample.y);
    result.right = std::max(result.right, sample.x);
    result.bottom = std::max(result.bottom, sample.y);
  }
  return result;
}

// JTS LineSegment.project/projectionFactor is the reference for finite segment
// projection: https://locationtech.github.io/jts/javadoc-1.18.0/org/locationtech/jts/geom/LineSegment.html
double SegmentDistance(Point2 point, Point2 a, Point2 b) {
  Point2 direction = Sub(b, a);
  double length2 = Dot(direction, direction);
  if (length2 == 0) return Distance(point, a);
  double t = std::clamp(Dot(Sub(point, a), direction) / length2, 0.0, 1.0);
  return Distance(point, {a.x + t * direction.x, a.y + t * direction.y});
}

// Xournal++'s ShapeRecognizer is the reference for bounded primitive fitting.
// This uses independent residual checks so a held handwritten symbol remains
// ink when no primitive explains its full path.
// https://github.com/xournalpp/xournalpp/tree/9882ffaaf2c012a1de4c33161eb4284468d84b9d/src/core/control/shaperecognizer
std::vector<InkPenSample> Path(const std::vector<InkPenSample> &raw,
                               const std::vector<Point2> &points) {
  std::vector<InkPenSample> result;
  result.reserve(points.size());
  for (size_t i = 0; i < points.size(); ++i) {
    double t = points.size() == 1 ? 0 : double(i) / double(points.size() - 1);
    InkPenSample sample = raw[std::min(raw.size() - 1, size_t(t * (raw.size() - 1)))];
    sample.x = points[i].x;
    sample.y = points[i].y;
    sample.time = raw.front().time + t * (raw.back().time - raw.front().time);
    sample.phase = i == 0 ? INK_PHASE_BEGIN : i + 1 == points.size() ? INK_PHASE_END : INK_PHASE_MOVE;
    sample.id = i == 0 ? raw.front().id : i + 1 == points.size() ? raw.back().id : 0;
    result.push_back(sample);
  }
  return result;
}

void Simplify(const std::vector<InkPenSample> &raw, size_t first, size_t last,
              double tolerance, std::vector<size_t> &vertices) {
  if (last <= first + 1) return;
  double maximum = 0;
  size_t farthest = first;
  for (size_t i = first + 1; i < last; ++i) {
    double distance = SegmentDistance(At(raw[i]), At(raw[first]), At(raw[last]));
    if (distance > maximum) { maximum = distance; farthest = i; }
  }
  if (maximum <= tolerance) return;
  Simplify(raw, first, farthest, tolerance, vertices);
  vertices.push_back(farthest);
  Simplify(raw, farthest, last, tolerance, vertices);
}

std::optional<std::vector<InkPenSample>> Line(const std::vector<InkPenSample> &raw,
                                               double diagonal, double scale) {
  Point2 first = At(raw.front()), last = At(raw.back());
  if (Distance(first, last) < 24 / scale) return std::nullopt;
  double error2 = 0;
  for (const auto &sample : raw)
    error2 += std::pow(SegmentDistance(At(sample), first, last), 2);
  if (std::sqrt(error2 / raw.size()) > std::max(2.5 / scale, diagonal * 0.045))
    return std::nullopt;
  return Path(raw, {first, last});
}

std::optional<std::vector<InkPenSample>> Ellipse(const std::vector<InkPenSample> &raw,
                                                  Bounds bounds, double scale) {
  const double rx = bounds.Width() / 2, ry = bounds.Height() / 2;
  if (rx < 10 / scale || ry < 10 / scale) return std::nullopt;
  Point2 center{bounds.left + rx, bounds.top + ry};
  double error2 = 0, winding = 0;
  for (size_t i = 0; i < raw.size(); ++i) {
    const double x = (raw[i].x - center.x) / rx;
    const double y = (raw[i].y - center.y) / ry;
    error2 += std::pow(std::hypot(x, y) - 1, 2);
    if (i) winding += Cross(Sub(At(raw[i - 1]), center), Sub(At(raw[i]), center));
  }
  if (std::sqrt(error2 / raw.size()) > 0.18 || std::abs(winding) < rx * ry * 3.5)
    return std::nullopt;
  double start = std::atan2((raw.front().y - center.y) / ry,
                            (raw.front().x - center.x) / rx);
  double direction = winding >= 0 ? 1 : -1;
  std::vector<Point2> points;
  for (int i = 0; i <= 64; ++i) {
    double angle = start + direction * 2 * std::numbers::pi * i / 64;
    points.push_back({center.x + rx * std::cos(angle), center.y + ry * std::sin(angle)});
  }
  return Path(raw, points);
}

std::optional<std::vector<InkPenSample>> Polygon(const std::vector<InkPenSample> &raw,
                                                  double diagonal, double scale) {
  // Splitting the closed loop at its farthest point avoids the zero length
  // baseline that a whole-loop Douglas-Peucker pass would have.
  size_t opposite = 0;
  for (size_t i = 1; i < raw.size(); ++i)
    if (Distance(At(raw[i]), At(raw.front())) > Distance(At(raw[opposite]), At(raw.front()))) opposite = i;
  if (opposite == 0 || opposite + 1 == raw.size()) return std::nullopt;
  std::vector<size_t> vertices{0};
  const double tolerance = std::max(2.5 / scale, diagonal * 0.035);
  Simplify(raw, 0, opposite, tolerance, vertices);
  vertices.push_back(opposite);
  Simplify(raw, opposite, raw.size() - 1, tolerance, vertices);
  vertices.push_back(raw.size() - 1);
  if (vertices.size() < 4 || vertices.size() > 9) return std::nullopt;
  double error2 = 0;
  for (size_t section = 1; section < vertices.size(); ++section)
    for (size_t i = vertices[section - 1]; i <= vertices[section]; ++i)
      error2 += std::pow(SegmentDistance(At(raw[i]), At(raw[vertices[section - 1]]),
                                         At(raw[vertices[section]])), 2);
  if (std::sqrt(error2 / raw.size()) > tolerance) return std::nullopt;
  std::vector<Point2> points;
  for (size_t index : vertices) points.push_back(At(raw[index]));
  points.back() = points.front();
  return Path(raw, points);
}

std::optional<std::vector<InkPenSample>> Arc(const std::vector<InkPenSample> &raw,
                                              double diagonal, double scale) {
  Point2 a = At(raw.front()), b = At(raw.back());
  if (Distance(a, b) < 24 / scale) return std::nullopt;
  std::vector<double> lengths(raw.size(), 0);
  for (size_t i = 1; i < raw.size(); ++i)
    lengths[i] = lengths[i - 1] + Distance(At(raw[i]), At(raw[i - 1]));
  if (lengths.back() < 1.1 * Distance(a, b)) return std::nullopt;
  Point2 numerator{0, 0};
  double denominator = 0;
  for (size_t i = 1; i + 1 < raw.size(); ++i) {
    double t = lengths[i] / lengths.back();
    double coefficient = 2 * t * (1 - t);
    Point2 fixed{(1 - t) * (1 - t) * a.x + t * t * b.x,
                 (1 - t) * (1 - t) * a.y + t * t * b.y};
    numerator.x += coefficient * (raw[i].x - fixed.x);
    numerator.y += coefficient * (raw[i].y - fixed.y);
    denominator += coefficient * coefficient;
  }
  if (denominator == 0) return std::nullopt;
  Point2 control{numerator.x / denominator, numerator.y / denominator};
  if (SegmentDistance(control, a, b) < std::max(7 / scale, diagonal * 0.12))
    return std::nullopt;
  double error2 = 0;
  for (size_t i = 0; i < raw.size(); ++i) {
    double t = lengths[i] / lengths.back();
    Point2 fit{(1 - t) * (1 - t) * a.x + 2 * t * (1 - t) * control.x + t * t * b.x,
               (1 - t) * (1 - t) * a.y + 2 * t * (1 - t) * control.y + t * t * b.y};
    error2 += std::pow(Distance(At(raw[i]), fit), 2);
  }
  if (std::sqrt(error2 / raw.size()) > std::max(3 / scale, diagonal * 0.06))
    return std::nullopt;
  std::vector<Point2> points;
  for (int i = 0; i <= 32; ++i) {
    double t = double(i) / 32;
    points.push_back({(1 - t) * (1 - t) * a.x + 2 * t * (1 - t) * control.x + t * t * b.x,
                      (1 - t) * (1 - t) * a.y + 2 * t * (1 - t) * control.y + t * t * b.y});
  }
  return Path(raw, points);
}

}  // namespace

std::optional<std::vector<InkPenSample>> RecognizeHeldStroke(
    const std::vector<InkPenSample> &samples, double view_scale) {
  if (samples.size() < 4 || !(view_scale > 0)) return std::nullopt;
  const InkPenSample &last = samples.back();
  size_t moving = samples.size() - 1;
  while (moving > 0 && Distance(At(samples[moving - 1]), At(last)) < 3 / view_scale)
    --moving;
  if (moving == 0 || last.time - samples[moving - 1].time < 450) return std::nullopt;
  std::vector<InkPenSample> raw(samples.begin(), samples.begin() + moving + 1);
  if (raw.size() < 3) return std::nullopt;
  Bounds bounds = Extent(raw);
  double diagonal = bounds.Diagonal();
  if (diagonal < 24 / view_scale) return std::nullopt;
  if (auto fit = Line(raw, diagonal, view_scale)) return fit;
  bool closed = Distance(At(raw.front()), At(raw.back())) < diagonal * 0.14;
  if (closed) {
    if (auto fit = Ellipse(raw, bounds, view_scale)) return fit;
    return Polygon(raw, diagonal, view_scale);
  }
  return Arc(raw, diagonal, view_scale);
}

bool IsEraseScribble(const std::vector<InkPenSample> &samples, double view_scale) {
  if (samples.size() < 7 || !(view_scale > 0)) return false;
  Bounds bounds = Extent(samples);
  if (bounds.Width() < 28 / view_scale || bounds.Width() < bounds.Height() * 1.5) return false;
  int reversals = 0, direction = 0;
  double travel = 0;
  for (size_t i = 1; i < samples.size(); ++i) {
    double dx = samples[i].x - samples[i - 1].x;
    travel += Distance(At(samples[i]), At(samples[i - 1]));
    int next = dx > 3 / view_scale ? 1 : dx < -3 / view_scale ? -1 : 0;
    if (next && direction && next != direction) ++reversals;
    if (next) direction = next;
  }
  return reversals >= 3 && travel > bounds.Width() * 3.5;
}

}  // namespace ink_engine
