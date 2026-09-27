// Page backgrounds generated from ruling parameters, and the built-in
// templates (docs/FORMAT.md, Background and Other files). The rule layer
// follows Write syncscribble/page.cpp:152-205 Page::generateRuleLayer; the
// presets follow Write syncscribble/rulingdialog.cpp:166-193 (styluslabs/Write
// 401b65d), converted at 0.48 pt per Write unit (150 units per inch).
#pragma once

#include <optional>
#include <string>
#include <vector>

#include "document/document.h"
#include "document/ids.h"

namespace ink_engine {

struct RulingSpec {
  Ruling ruling = Ruling::kBlank;
  double y_ruling = 0;     // pt between lines, rows of a grid or of dots
  double x_ruling = 0;     // pt between columns; 0 without columns
  double margin_left = 0;  // pt; 0 without a margin line
};

// The background of a `width` × `height` page: the paper and the ruling.
// Lines start one spacing in from the top and left edges. Blank-page working
// grids belong to the active ruled gesture, not the saved background.
Background MakeBackground(const RulingSpec &spec, double width, double height);

struct BuiltinTemplate {
  const char *name;
  RulingSpec spec;
};

// blank, lined-wide/medium/narrow, grid-coarse/medium/fine, dotted.
const std::vector<BuiltinTemplate> &BuiltinTemplates();

// The notebook written to Notes/.templates/<name>/ for a built-in template:
// one A4 page with its background. Null for an unknown name.
std::optional<Document> BuiltinTemplateNotebook(const std::string &name, IdGenerator &ids);

}  // namespace ink_engine
