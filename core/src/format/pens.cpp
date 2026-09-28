#include "format/pens.h"

#include <cmath>

#include <nlohmann/json.hpp>

#include "format/numbers.h"
#include "format/page_svg.h"

namespace ink_engine {
namespace {

using Json = nlohmann::ordered_json;

// A number rounded to `precision` decimals, with no trailing zeros as in page
// files: nlohmann writes a double as the shortest text that reads back as it,
// and a whole number as an integer.
Json Number(double value, int precision) {
  double scale = std::pow(10.0, precision);
  double rounded = std::round(value * scale) / scale;
  if (rounded == std::floor(rounded)) return int64_t(rounded);
  return rounded;
}

}  // namespace

// The rail's Pen, Thick pen and Highlighter (docs/specs/tablet-ui.md,
// Editor) on the three stock brushes of Google Cahier
// app/src/main/java/com/example/cahier/features/drawing/DrawingToolbox.kt:483-505
// (android/cahier 209db71).
std::vector<PenPreset> DefaultPens() {
  return {
      {"pen", "Pen", "pressure-pen", 1, {0x1A, 0x1A, 0x1A}, 1, 1.2},
      {"thick-pen", "Thick pen", "marker", 1, {0x1A, 0x1A, 0x1A}, 1, 2.4},
      {"highlighter", "Highlighter", "highlighter", 1, {0xFF, 0xE0, 0x66}, 0.35, 9.6},
  };
}

std::vector<PenPreset> ReadPens(std::string_view bytes) {
  std::vector<PenPreset> pens;
  for (const Json &pen : Json::parse(bytes)) {
    pens.push_back({.id = pen.at("id").get<std::string>(),
                    .name = pen.at("name").get<std::string>(),
                    .brush = pen.at("brush").get<std::string>(),
                    .brush_version = pen.at("brushVersion").get<int>(),
                    .color = ReadColor(pen.at("color").get<std::string>()),
                    .opacity = pen.at("opacity").get<double>(),
                    .size = pen.at("size").get<double>()});
  }
  return pens;
}

std::string WritePens(const std::vector<PenPreset> &pens) {
  Json json = Json::array();
  for (const PenPreset &pen : pens) {
    json.push_back({{"id", pen.id},
                    {"name", pen.name},
                    {"brush", pen.brush},
                    {"brushVersion", pen.brush_version},
                    {"color", WriteColor(pen.color)},
                    {"opacity", Number(pen.opacity, kAnglePrecision)},
                    {"size", Number(pen.size, kCoordinatePrecision)}});
  }
  return json.dump(2) + "\n";
}

}  // namespace ink_engine
