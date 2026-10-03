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

Json Preset(const PenPreset &pen) {
  return {{"brush", pen.brush},
          {"brushVersion", pen.brush_version},
          {"color", WriteColor(pen.color)},
          {"opacity", Number(pen.opacity, kAnglePrecision)},
          {"size", Number(pen.size, kCoordinatePrecision)},
          {"modes", pen.modes},
          {"smoothingMs", Number(pen.smoothing_ms, kCoordinatePrecision)}};
}

PenPreset Preset(const Json &pen) {
  return {.brush = pen.at("brush").get<std::string>(),
          .brush_version = pen.at("brushVersion").get<int>(),
          .color = ReadColor(pen.at("color").get<std::string>()),
          .opacity = pen.at("opacity").get<double>(),
          .size = pen.at("size").get<double>(),
          .modes = pen.at("modes").get<uint32_t>(),
          .smoothing_ms = pen.at("smoothingMs").get<double>()};
}

}  // namespace

// The pen, marker and highlighter on three stock brushes of Google Cahier
// app/src/main/java/com/example/cahier/features/drawing/DrawingToolbox.kt:475-503
// (android/cahier 209db71); the palette is the first swatches of the editor
// mockup (docs/specs/tablet-ui.md, Editor).
PenFile DefaultPens() {
  return {.pen = {"pressure-pen", 1, {0x1A, 0x1A, 0x1A}, 1, 1.2},
          .marker = {"marker", 1, {0x1A, 0x1A, 0x1A}, 1, 1.2},
          .highlighter = {"highlighter", 1, {0xFF, 0xE0, 0x66}, 0.35, 9.6},
          .palette = {{0x1A, 0x1A, 0x1A},
                      {0x1F, 0x4F, 0xB5},
                      {0xD9, 0x2D, 0x39},
                      {0x29, 0x95, 0x5B},
                      {0xFF, 0xCF, 0x26}},
          .saved = {}};
}

PenFile ReadPens(std::string_view bytes) {
  Json json = Json::parse(bytes);
  PenFile pens{.pen = Preset(json.at("pen")),
               .marker = Preset(json.at("marker")),
               .highlighter = Preset(json.at("highlighter"))};
  for (const Json &color : json.at("palette")) pens.palette.push_back(ReadColor(color.get<std::string>()));
  for (const Json &pen : json.at("saved")) pens.saved.push_back(Preset(pen));
  return pens;
}

std::string WritePens(const PenFile &pens) {
  Json palette = Json::array();
  for (const Rgb &color : pens.palette) palette.push_back(WriteColor(color));
  Json saved = Json::array();
  for (const PenPreset &pen : pens.saved) saved.push_back(Preset(pen));
  Json json = {{"pen", Preset(pens.pen)},
               {"marker", Preset(pens.marker)},
               {"highlighter", Preset(pens.highlighter)},
               {"palette", palette},
               {"saved", saved}};
  return json.dump(2) + "\n";
}

}  // namespace ink_engine
