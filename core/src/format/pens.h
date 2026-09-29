// The tool settings file Notes/.pens.json (docs/FORMAT.md, Other files): the
// pen, marker and highlighter settings, the color palette, and the saved pens.
#pragma once

#include <string>
#include <string_view>
#include <vector>

#include "document/document.h"

namespace ink_engine {

struct PenPreset {
  std::string brush;  // google/ink stock brush family, as mn:brush
  int brush_version = 1;
  Rgb color;
  double opacity = 1;  // the strokes' fill-opacity
  double size = 0;     // pt
  bool operator==(const PenPreset &) const = default;
};

struct PenFile {
  PenPreset pen;
  PenPreset marker;
  PenPreset highlighter;
  std::vector<Rgb> palette;
  std::vector<PenPreset> saved;
  bool operator==(const PenFile &) const = default;
};

// The settings written on first use (issue #25).
PenFile DefaultPens();

// Throws nlohmann::json::exception on bad JSON or a missing key.
PenFile ReadPens(std::string_view bytes);

// Keys in FORMAT.md order, two-space indent, one trailing newline; size with
// 2 decimals and opacity with 3, as in page files.
std::string WritePens(const PenFile &pens);

}  // namespace ink_engine
