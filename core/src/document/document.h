// The notebook document as an immutable value (immer). Layout and meaning of
// every field: docs/FORMAT.md.
#pragma once

#include <array>
#include <cstdint>
#include <optional>
#include <string>
#include <variant>
#include <vector>

#include <immer/box.hpp>
#include <immer/flex_vector.hpp>

namespace ink_engine {

struct Point {
  double x = 0, y = 0;
  bool operator==(const Point &) const = default;
};

// SVG transform matrix(a,b,c,d,e,f). Written as translate(e,f) when a=d=1, b=c=0.
struct Transform {
  double a = 1, b = 0, c = 0, d = 1, e = 0, f = 0;
  bool IsIdentity() const { return *this == Transform{}; }
  bool IsTranslation() const { return a == 1 && b == 0 && c == 0 && d == 1; }
  bool operator==(const Transform &) const = default;
};

struct Rgb {
  uint8_t r = 0, g = 0, b = 0;
  bool operator==(const Rgb &) const = default;
};

// One closed subpath of an outline, in stroke-local coordinates.
using Polyline = std::vector<Point>;

// InkML channels, in file order (FORMAT.md, Page SVG).
enum Channel : uint32_t {
  kChannelX = 1 << 0,
  kChannelY = 1 << 1,
  kChannelT = 1 << 2,
  kChannelF = 1 << 3,
  kChannelOE = 1 << 4,
  kChannelOA = 1 << 5,
  kChannelOR = 1 << 6,
};
inline constexpr std::array<std::pair<Channel, const char *>, 7> kChannels = {{
    {kChannelX, "X"}, {kChannelY, "Y"}, {kChannelT, "T"}, {kChannelF, "F"},
    {kChannelOE, "OE"}, {kChannelOA, "OA"}, {kChannelOR, "OR"},
}};

// One input sample. Only the channels in the stroke's channel set are meaningful.
struct Sample {
  double x = 0, y = 0;  // pt, stroke-local
  double t = 0;         // ms since the stroke's mn:time
  double force = 0;     // 0..1
  double altitude = 0;  // rad
  double azimuth = 0;   // rad
  double roll = 0;      // rad
  bool operator==(const Sample &) const = default;
};

struct Stroke {
  std::string id;
  Transform transform;
  Rgb fill;
  std::optional<double> fill_opacity;
  std::string brush;  // google/ink stock brush family, e.g. "pressure-pen"
  int brush_version = 1;
  double size = 0;
  std::string time;  // UTC ISO 8601 start time
  std::vector<Polyline> outline;
  uint32_t channels = kChannelX | kChannelY;
  std::vector<Sample> samples;
  bool operator==(const Stroke &) const = default;
};

enum class ShapeKind { kLine, kPolygon, kRect, kEllipse, kPath };

// A recognized shape (FORMAT.md, Shape elements). `points` holds, by kind:
// line: 2 endpoints; polygon: vertices; rect: origin and size;
// ellipse: center and radii; path: the arrow's subpaths in `path`.
struct Shape {
  std::string id;
  ShapeKind kind = ShapeKind::kLine;
  Transform transform;
  Rgb stroke;
  double stroke_width = 0;
  std::vector<Point> points;
  std::vector<Polyline> path;
  bool operator==(const Shape &) const = default;
};

struct Image {
  std::string id;
  std::string href;  // path relative to the page file, e.g. "../assets/p0017.png"
  Transform transform;
  double x = 0, y = 0, width = 0, height = 0;
  bool operator==(const Image &) const = default;
};

struct Text {
  std::string id;
  Transform transform;
  Rgb fill{26, 26, 26};
  double x = 0, y = 0;  // baseline of the first line, in pt
  double size = 18;    // font size in pt
  std::vector<std::string> lines;
  bool operator==(const Text &) const = default;
};

struct Element;
using Elements = immer::flex_vector<immer::box<Element>>;

struct Bookmark {
  std::string id;
  Elements children;
  bool operator==(const Bookmark &) const = default;
};

struct Figure {
  std::string id;
  Transform transform;
  std::string scene_href;  // relative to the page SVG
  std::string tikz_href;   // relative to the page SVG
  Elements children;       // standalone SVG view, including original ink and InkML
  bool operator==(const Figure &) const = default;
};

struct Link {
  std::string href;
  Elements children;
  bool operator==(const Link &) const = default;
};

struct Element {
  std::variant<Stroke, Shape, Image, Text, Bookmark, Figure, Link> value;
  bool operator==(const Element &) const = default;
};

enum class Ruling { kBlank, kLined, kGrid, kDotted };

// A ruling line as it appears in g#background.
struct RulingPath {
  std::vector<Polyline> d;  // open polylines
  Rgb stroke;
  double stroke_width = 0;
  bool round_caps = false;  // stroke-linecap="round": dots are zero-length subpaths
  bool operator==(const RulingPath &) const = default;
};

struct Background {
  Ruling ruling = Ruling::kBlank;
  double y_ruling = 0, y_offset = 0, x_ruling = 0, margin_left = 0;
  Rgb fill{255, 255, 255};
  std::optional<Image> image;  // an imported PDF page
  std::vector<RulingPath> lines;
  bool operator==(const Background &) const = default;
};

struct LayerContent {
  std::string layer_id;
  Elements elements;
  bool operator==(const LayerContent &) const = default;
};

struct Page {
  std::string id;
  std::string file;  // "pages/0001.svg"
  double width = 0, height = 0;  // pt
  Background background;
  std::vector<LayerContent> layers;  // in notebook.json layer order
  bool unlisted = false;
  // A page file that did not parse: shown with this message, never written.
  std::optional<std::string> error;
  bool operator==(const Page &) const = default;
};

struct Layer {
  std::string id;
  std::string name;
  bool hidden = false;
  bool locked = false;
  bool operator==(const Layer &) const = default;
};

// pageSize: "A4", "Letter", or [width, height] in pt.
using PageSize = std::variant<std::string, std::array<double, 2>>;

struct Notebook {
  std::string title;
  PageSize page_size = std::string("A4");
  std::string template_name;
  std::vector<Layer> layers;
  bool operator==(const Notebook &) const = default;
};

struct Document {
  Notebook notebook;
  immer::flex_vector<immer::box<Page>> pages;  // listed pages, then unlisted
  bool operator==(const Document &) const = default;
};

}  // namespace ink_engine
