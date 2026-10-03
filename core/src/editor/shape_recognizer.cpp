#include "editor/shape_recognizer.h"

#include <algorithm>
#include <cmath>
#include <limits>
#include <numbers>

#include <Bezier/bezier.h>
#include <dollar.hpp>
#include <opencv2/imgproc.hpp>

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

std::vector<cv::Point2f> CvPoints(const std::vector<InkPenSample> &samples) {
  std::vector<cv::Point2f> points;
  points.reserve(samples.size());
  for (const auto &sample : samples)
    points.emplace_back(sample.x, sample.y);
  return points;
}

struct Bounds {
  double left, top, right, bottom;
  double Width() const { return right - left; }
  double Height() const { return bottom - top; }
  double Diagonal() const { return std::hypot(Width(), Height()); }
};

Bounds Extent(const std::vector<InkPenSample> &samples) {
  Bounds result{samples.front().x, samples.front().y, samples.front().x,
                samples.front().y};
  for (const auto &sample : samples) {
    result.left = std::min(result.left, sample.x);
    result.top = std::min(result.top, sample.y);
    result.right = std::max(result.right, sample.x);
    result.bottom = std::max(result.bottom, sample.y);
  }
  return result;
}

// JTS LineSegment.project/projectionFactor is the reference for finite segment
// projection:
// https://locationtech.github.io/jts/javadoc-1.18.0/org/locationtech/jts/geom/LineSegment.html
double SegmentDistance(Point2 point, Point2 a, Point2 b) {
  Point2 direction = Sub(b, a);
  double length2 = Dot(direction, direction);
  if (length2 == 0)
    return Distance(point, a);
  double t = std::clamp(Dot(Sub(point, a), direction) / length2, 0.0, 1.0);
  return Distance(point, {a.x + t * direction.x, a.y + t * direction.y});
}

std::vector<InkPenSample> Path(const std::vector<InkPenSample> &raw,
                               const std::vector<Point2> &points) {
  std::vector<InkPenSample> result;
  result.reserve(points.size());
  for (size_t i = 0; i < points.size(); ++i) {
    double t = points.size() == 1 ? 0 : double(i) / double(points.size() - 1);
    InkPenSample sample =
        raw[std::min(raw.size() - 1, size_t(t * (raw.size() - 1)))];
    sample.x = points[i].x;
    sample.y = points[i].y;
    sample.time = raw.front().time + t * (raw.back().time - raw.front().time);
    sample.phase = i == 0                   ? INK_PHASE_BEGIN
                   : i + 1 == points.size() ? INK_PHASE_END
                                            : INK_PHASE_MOVE;
    sample.id = i == 0                   ? raw.front().id
                : i + 1 == points.size() ? raw.back().id
                                         : 0;
    result.push_back(sample);
  }
  return result;
}

enum class Primitive { kLine, kEllipse, kPolygon, kArc };

struct ReferenceStrokes {
  std::vector<dollar::Stroke> strokes;
  std::vector<Primitive> kinds;
};

const ReferenceStrokes &References() {
  static const ReferenceStrokes references = [] {
    ReferenceStrokes result;
    auto add = [&](Primitive kind, std::vector<dollar::Point> points) {
      result.strokes.emplace_back(points, dollar::Orientation::Insensitive);
      result.kinds.push_back(kind);
      std::reverse(points.begin(), points.end());
      result.strokes.emplace_back(points, dollar::Orientation::Insensitive);
      result.kinds.push_back(kind);
    };
    add(Primitive::kLine, {{0, 0}, {100, 0}});
    for (float aspect : {1.0f, 1.8f, 2.8f}) {
      std::vector<dollar::Point> points;
      for (int i = 0; i <= 32; ++i) {
        const float angle = 2 * std::numbers::pi_v<float> * i / 32;
        points.emplace_back(100 * std::cos(angle),
                            100 * std::sin(angle) / aspect);
      }
      add(Primitive::kEllipse, std::move(points));
    }
    for (int sides = 3; sides <= 12; ++sides) {
      std::vector<dollar::Point> points;
      for (int i = 0; i <= sides; ++i) {
        const float angle = 2 * std::numbers::pi_v<float> * i / sides;
        points.emplace_back(100 * std::cos(angle), 100 * std::sin(angle));
      }
      add(Primitive::kPolygon, std::move(points));
    }
    for (float depth : {75.0f, 150.0f}) {
      std::vector<dollar::Point> points;
      for (int i = 0; i <= 16; ++i) {
        const float t = float(i) / 16;
        points.emplace_back(100 * t, -depth * t * (1 - t));
      }
      add(Primitive::kArc, std::move(points));
    }
    return result;
  }();
  return references;
}

std::optional<Primitive> Classify(const std::vector<InkPenSample> &raw) {
  std::vector<dollar::Point> points;
  points.reserve(raw.size());
  for (const auto &sample : raw) {
    dollar::Point point{sample.x, sample.y};
    if (points.empty() ||
        std::hypot(point.first - points.back().first,
                   point.second - points.back().second) > 0.01f)
      points.push_back(point);
  }
  if (points.size() < 3)
    return std::nullopt;
  const ReferenceStrokes &references = References();
  dollar::Stroke stroke(points, dollar::Orientation::Insensitive);
  auto [match, score] = dollar::recognize(stroke, references.strokes.begin(),
                                          references.strokes.end());
  if (match == references.strokes.end() || score < 1.6f)
    return std::nullopt;
  return references.kinds[std::distance(references.strokes.begin(), match)];
}

std::optional<std::vector<InkPenSample>>
Line(const std::vector<InkPenSample> &raw, double diagonal, double scale) {
  if (Distance(At(raw.front()), At(raw.back())) < 24 / scale)
    return std::nullopt;
  cv::Vec4f fit;
  cv::fitLine(CvPoints(raw), fit, cv::DIST_L2, 0, 0.01, 0.01);
  Point2 direction{fit[0], fit[1]}, origin{fit[2], fit[3]};
  auto project = [&](Point2 point) {
    const double distance = Dot(Sub(point, origin), direction);
    return Point2{origin.x + distance * direction.x,
                  origin.y + distance * direction.y};
  };
  Point2 first = project(At(raw.front())), last = project(At(raw.back()));
  double error2 = 0;
  for (const auto &sample : raw)
    error2 += std::pow(SegmentDistance(At(sample), first, last), 2);
  if (std::sqrt(error2 / raw.size()) > std::max(2.5 / scale, diagonal * 0.045))
    return std::nullopt;
  return Path(raw, {first, last});
}

std::optional<std::vector<InkPenSample>>
Ellipse(const std::vector<InkPenSample> &raw, double scale) {
  if (raw.size() < 5)
    return std::nullopt;
  const cv::RotatedRect fit = cv::fitEllipse(CvPoints(raw));
  const double rx = fit.size.width / 2, ry = fit.size.height / 2;
  if (rx < 10 / scale || ry < 10 / scale)
    return std::nullopt;
  Point2 center{fit.center.x, fit.center.y};
  const double rotation = fit.angle * std::numbers::pi / 180;
  const double cosine = std::cos(rotation), sine = std::sin(rotation);
  auto local = [&](Point2 point) {
    Point2 shifted = Sub(point, center);
    return Point2{shifted.x * cosine + shifted.y * sine,
                  -shifted.x * sine + shifted.y * cosine};
  };
  double error2 = 0, winding = 0;
  for (size_t i = 0; i < raw.size(); ++i) {
    const Point2 point = local(At(raw[i]));
    const double x = point.x / rx, y = point.y / ry;
    error2 += std::pow(std::hypot(x, y) - 1, 2);
    if (i)
      winding += Cross(Sub(At(raw[i - 1]), center), Sub(At(raw[i]), center));
  }
  if (std::sqrt(error2 / raw.size()) > 0.18 ||
      std::abs(winding) < rx * ry * 3.5)
    return std::nullopt;
  const Point2 local_start = local(At(raw.front()));
  double start = std::atan2(local_start.y / ry, local_start.x / rx);
  double direction = winding >= 0 ? 1 : -1;
  std::vector<Point2> points;
  for (int i = 0; i <= 64; ++i) {
    double angle = start + direction * 2 * std::numbers::pi * i / 64;
    const double x = rx * std::cos(angle), y = ry * std::sin(angle);
    points.push_back(
        {center.x + x * cosine - y * sine, center.y + x * sine + y * cosine});
  }
  return Path(raw, points);
}

std::optional<std::vector<InkPenSample>>
Polygon(const std::vector<InkPenSample> &raw, double diagonal, double scale) {
  const double tolerance = std::max(2.5 / scale, diagonal * 0.035);
  std::vector<cv::Point2f> vertices;
  cv::approxPolyDP(CvPoints(raw), vertices, tolerance, true);
  if (vertices.size() < 3 || vertices.size() > 12)
    return std::nullopt;
  double error2 = 0;
  for (const auto &sample : raw)
    error2 += std::pow(
        cv::pointPolygonTest(vertices, cv::Point2f(sample.x, sample.y), true),
        2);
  if (std::sqrt(error2 / raw.size()) > tolerance)
    return std::nullopt;
  std::vector<Point2> points;
  for (const auto &vertex : vertices)
    points.push_back({vertex.x, vertex.y});
  points.push_back(points.front());
  return Path(raw, points);
}

std::optional<std::vector<InkPenSample>>
Arc(const std::vector<InkPenSample> &raw, double diagonal, double scale) {
  Point2 a = At(raw.front()), b = At(raw.back());
  if (Distance(a, b) < 24 / scale)
    return std::nullopt;
  Bezier::PointVector source;
  source.reserve(raw.size());
  for (const auto &sample : raw)
    source.emplace_back(sample.x, sample.y);
  const Bezier::Curve fit = Bezier::Curve::fromPolyline(source, 2);
  const Bezier::PointVector controls = fit.controlPoints();
  if (controls.size() != 3)
    return std::nullopt;
  Point2 control{controls[1].x(), controls[1].y()};
  if (SegmentDistance(control, a, b) < std::max(7 / scale, diagonal * 0.12))
    return std::nullopt;
  double error2 = 0;
  for (const auto &point : source)
    error2 += std::pow(fit.distance(point), 2);
  if (std::sqrt(error2 / raw.size()) > std::max(3 / scale, diagonal * 0.06))
    return std::nullopt;
  std::vector<Point2> points;
  for (int i = 0; i <= 32; ++i) {
    const Bezier::Point point = fit.valueAt(double(i) / 32);
    points.push_back({point.x(), point.y()});
  }
  return Path(raw, points);
}

} // namespace

std::optional<std::vector<InkPenSample>>
RecognizeHeldStroke(const std::vector<InkPenSample> &samples,
                    double view_scale) {
  if (samples.size() < 4 || !(view_scale > 0))
    return std::nullopt;
  const InkPenSample &last = samples.back();
  size_t moving = samples.size() - 1;
  while (moving > 0 &&
         Distance(At(samples[moving - 1]), At(last)) < 3 / view_scale)
    --moving;
  if (moving == 0 || last.time - samples[moving - 1].time < 450)
    return std::nullopt;
  std::vector<InkPenSample> raw(samples.begin(), samples.begin() + moving + 1);
  if (raw.size() < 3)
    return std::nullopt;
  Bounds bounds = Extent(raw);
  double diagonal = bounds.Diagonal();
  if (diagonal < 24 / view_scale)
    return std::nullopt;
  const std::optional<Primitive> kind = Classify(raw);
  if (!kind)
    return std::nullopt;
  bool closed = Distance(At(raw.front()), At(raw.back())) < diagonal * 0.14;
  if (closed) {
    if (*kind == Primitive::kEllipse)
      return Ellipse(raw, view_scale);
    if (*kind == Primitive::kPolygon)
      return Polygon(raw, diagonal, view_scale);
    return std::nullopt;
  }
  if (*kind == Primitive::kLine)
    return Line(raw, diagonal, view_scale);
  if (*kind == Primitive::kArc)
    return Arc(raw, diagonal, view_scale);
  return std::nullopt;
}

bool IsEraseScribble(const std::vector<InkPenSample> &samples,
                     double view_scale) {
  if (samples.size() < 7 || !(view_scale > 0))
    return false;
  Point2 mean{0, 0};
  for (const auto &sample : samples) {
    mean.x += sample.x;
    mean.y += sample.y;
  }
  mean.x /= samples.size();
  mean.y /= samples.size();
  double xx = 0, xy = 0, yy = 0;
  for (const auto &sample : samples) {
    const double x = sample.x - mean.x, y = sample.y - mean.y;
    xx += x * x;
    xy += x * y;
    yy += y * y;
  }
  const double angle = 0.5 * std::atan2(2 * xy, xx - yy);
  Point2 axis{std::cos(angle), std::sin(angle)};
  Point2 across{-axis.y, axis.x};
  double minimum = std::numeric_limits<double>::infinity();
  double maximum = -minimum, cross_min = minimum, cross_max = -minimum;
  for (const auto &sample : samples) {
    const double along = Dot(Sub(At(sample), mean), axis);
    const double across_position = Dot(Sub(At(sample), mean), across);
    minimum = std::min(minimum, along);
    maximum = std::max(maximum, along);
    cross_min = std::min(cross_min, across_position);
    cross_max = std::max(cross_max, across_position);
  }
  const double extent = maximum - minimum;
  if (extent < 28 / view_scale || extent < (cross_max - cross_min) * 1.3)
    return false;
  int reversals = 0, direction = 0;
  double travel = 0;
  for (size_t i = 1; i < samples.size(); ++i) {
    double dx = Dot(Sub(At(samples[i]), At(samples[i - 1])), axis);
    travel += Distance(At(samples[i]), At(samples[i - 1]));
    int next = dx > 3 / view_scale ? 1 : dx < -3 / view_scale ? -1 : 0;
    if (next && direction && next != direction)
      ++reversals;
    if (next)
      direction = next;
  }
  return reversals >= 3 && travel > extent * 3.5;
}

} // namespace ink_engine
