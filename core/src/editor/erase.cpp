#include "editor/erase.h"

#include <algorithm>
#include <cmath>
#include <numbers>
#include <optional>

#include "editor/editor.h"
#include "include/core/SkPathMeasure.h"
#include "strokes/clip.h"
#include "strokes/outline.h"

namespace ink_engine {
namespace {

using Section = std::pair<double, double>;

// The parameters t of a-b with |a + t(b - a) - c| <= r: the roots of the
// quadratic, as in Ericson, Real-Time Collision Detection (2005), §5.3.2
// IntersectRaySphere.
std::optional<Section> SegmentInDisk(Point a, Point b, Point c, double r) {
  double dx = b.x - a.x, dy = b.y - a.y, fx = a.x - c.x, fy = a.y - c.y;
  double qa = dx * dx + dy * dy, qb = 2 * (dx * fx + dy * fy), qc = fx * fx + fy * fy - r * r;
  if (qa == 0) return qc <= 0 ? std::optional<Section>({0, 1}) : std::nullopt;
  double discriminant = qb * qb - 4 * qa * qc;
  if (discriminant < 0) return std::nullopt;
  double root = std::sqrt(discriminant);
  return Section{(-qb - root) / (2 * qa), (-qb + root) / (2 * qa)};
}

// The parameters of a-b inside the rectangle swept by p-q widened by r on both
// sides: Liang–Barsky (strokes/clip.h) in the frame of p-q.
std::optional<Section> SegmentInBand(Point a, Point b, Point p, Point q, double r) {
  double length = std::hypot(q.x - p.x, q.y - p.y);
  if (length == 0) return std::nullopt;
  double ux = (q.x - p.x) / length, uy = (q.y - p.y) / length;
  auto along = [&](Point s) { return (s.x - p.x) * ux + (s.y - p.y) * uy; };
  auto across = [&](Point s) { return (s.y - p.y) * ux - (s.x - p.x) * uy; };
  double t1 = 0, t2 = 1;
  if (!ClipParameters(along(a), across(a), along(b), across(b),
                      {.left = 0, .top = -r, .right = length, .bottom = r}, t1, t2)) {
    return std::nullopt;
  }
  return Section{t1, t2};
}

// The parameters of a-b inside the capsule around p-q of radius r. The
// capsule is the union of the band and the two end disks; it is convex, so
// the parameters form one interval.
std::optional<Section> SegmentInCapsule(Point a, Point b, Point p, Point q, double r) {
  std::optional<Section> hit;
  for (std::optional<Section> part :
       {SegmentInDisk(a, b, p, r), SegmentInDisk(a, b, q, r), SegmentInBand(a, b, p, q, r)}) {
    if (!part) continue;
    double lo = std::max(part->first, 0.0), hi = std::min(part->second, 1.0);
    if (lo > hi) continue;
    hit = hit ? Section{std::min(hit->first, lo), std::max(hit->second, hi)} : Section{lo, hi};
  }
  return hit;
}

InkPenSample ToPenSample(const Sample &s) {
  return {.x = s.x, .y = s.y, .time = s.t, .pressure = float(s.force), .altitude = float(s.altitude),
          .azimuth = float(s.azimuth), .roll = float(s.roll)};
}

Sample FromPenSample(const InkPenSample &s) {
  return {.x = s.x, .y = s.y, .t = s.time, .force = s.pressure, .altitude = s.altitude,
          .azimuth = s.azimuth, .roll = s.roll};
}

// The sample at path parameter s.
Sample SampleAt(const std::vector<Sample> &samples, double s) {
  size_t i = std::min(size_t(s), samples.size() - 2);
  return FromPenSample(Interpolate(ToPenSample(samples[i]), ToPenSample(samples[i + 1]), s - i));
}

// Points along an ellipse's outline, about one per point of length, closed.
Polyline EllipsePoints(const Shape &shape) {
  SkPathMeasure measure(ShapePath(shape), /*forceClosed=*/true);
  float length = measure.getLength();
  size_t count = std::max<size_t>(8, size_t(std::ceil(length)));
  Polyline points;
  for (size_t i = 0; i <= count; ++i) {
    SkPoint at;
    measure.getPosTan(length * float(i % count) / float(count), &at, nullptr);
    points.push_back({at.x(), at.y()});
  }
  return points;
}

// A shape's geometry as polylines in its local coordinates, closed shapes
// ending at their first point.
std::vector<Polyline> ShapePolylines(const Shape &shape) {
  const std::vector<Point> &p = shape.points;
  switch (shape.kind) {
    case ShapeKind::kLine: return {p};
    case ShapeKind::kPolygon: {
      Polyline closed = p;
      if (!p.empty()) closed.push_back(p.front());
      return {closed};
    }
    case ShapeKind::kRect: {
      if (p.size() < 2) return {};
      double x = p[0].x, y = p[0].y, w = p[1].x, h = p[1].y;
      return {{{x, y}, {x + w, y}, {x + w, y + h}, {x, y + h}, {x, y}}};
    }
    case ShapeKind::kEllipse: return {EllipsePoints(shape)};
    case ShapeKind::kPath: return shape.path;
  }
  return {};
}

// Sample times along a shape: google/ink's sliding-window input model
// (brush_family.h, window_size 20 ms) then smooths over 1 pt of the geometry.
constexpr double kShapeMsPerPoint = 20;

}  // namespace

void EraseCapsule(const std::vector<Point> &path, Point p, Point q, double radius,
                  ErasedSections &erased) {
  using boost::icl::interval;
  if (path.size() == 1) {
    if (SegmentInCapsule(path[0], path[0], p, q, radius)) erased += interval<double>::closed(0, 0);
    return;
  }
  for (size_t i = 0; i + 1 < path.size(); ++i) {
    std::optional<Section> hit = SegmentInCapsule(path[i], path[i + 1], p, q, radius);
    if (hit) erased += interval<double>::closed(i + hit->first, i + hit->second);
  }
}

std::vector<std::pair<double, double>> RemainingSections(size_t count,
                                                         const ErasedSections &erased) {
  using boost::icl::interval;
  if (count == 0) return {};
  if (count == 1) return erased.empty() ? std::vector<Section>{{0, 0}} : std::vector<Section>{};
  ErasedSections remaining;
  remaining += interval<double>::closed(0, double(count - 1));
  remaining -= erased;
  std::vector<Section> sections;
  for (const auto &section : remaining) {
    if (section.upper() > section.lower()) sections.push_back({section.lower(), section.upper()});
  }
  return sections;
}

std::vector<Sample> SectionSamples(const std::vector<Sample> &samples, double from, double to) {
  if (samples.size() == 1) return samples;
  std::vector<Sample> section{SampleAt(samples, from)};
  for (size_t i = size_t(std::floor(from)) + 1; double(i) < to; ++i) section.push_back(samples[i]);
  section.push_back(SampleAt(samples, to));
  return section;
}

std::vector<Point> PagePath(const Stroke &stroke) {
  const Transform &m = stroke.transform;
  std::vector<Point> path;
  for (const Sample &s : stroke.samples) {
    path.push_back({m.a * s.x + m.c * s.y + m.e, m.b * s.x + m.d * s.y + m.f});
  }
  return path;
}

// Sample -> ink::StrokeInput as Editor::ToStrokeInput does for host samples: a
// channel the stroke does not record keeps google/ink's kNo* sentinel.
ink::Stroke InkStroke(const Stroke &stroke) {
  ink::StrokeInputBatch batch;
  for (const Sample &s : stroke.samples) {
    ink::StrokeInput input{
        .tool_type = ink::StrokeInput::ToolType::kStylus,
        .position = {float(s.x), float(s.y)},
        .elapsed_time = ink::Duration32::Millis(float(s.t)),
    };
    if (stroke.channels & kChannelF) input.pressure = float(s.force);
    if (stroke.channels & kChannelOE) {
      input.tilt = ink::Angle::Radians(std::numbers::pi_v<float> / 2 - float(s.altitude));
    }
    if (stroke.channels & kChannelOA) input.orientation = ink::Angle::Radians(float(s.azimuth));
    if (stroke.channels & kChannelOR) input.barrel_twist = ink::Angle::Radians(float(s.roll));
    // Append drops inputs out of order, as the live stroke does.
    (void)batch.Append(input);
  }
  Pen pen{.brush = BrushFromName(stroke.brush), .color = stroke.fill,
          .size = float(stroke.size), .smoothing_ms = float(stroke.smoothing_ms)};
  return ink::Stroke(MakeBrush(pen), batch);
}

void RebuildOutline(Stroke &stroke) { stroke.outline = StrokeOutline(InkStroke(stroke).GetShape()); }

std::vector<Stroke> ShapeStrokes(const Shape &shape, const std::string &time) {
  std::vector<Stroke> strokes;
  for (const Polyline &line : ShapePolylines(shape)) {
    if (line.empty()) continue;
    Stroke stroke{.transform = shape.transform, .fill = shape.stroke, .brush = "marker",
                  .size = shape.stroke_width, .time = time,
                  .channels = kChannelX | kChannelY | kChannelT};
    double t = 0;
    for (size_t i = 0; i < line.size(); ++i) {
      if (i > 0) t += kShapeMsPerPoint * std::hypot(line[i].x - line[i - 1].x, line[i].y - line[i - 1].y);
      stroke.samples.push_back({.x = line[i].x, .y = line[i].y, .t = t});
    }
    RebuildOutline(stroke);
    strokes.push_back(std::move(stroke));
  }
  return strokes;
}

}  // namespace ink_engine
