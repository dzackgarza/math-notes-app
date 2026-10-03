#include "document/templates.h"

#include "document/pages.h"

namespace ink_engine {
namespace {

// Paper and ruling look from docs/specs/tablet-ui.md ("Visual style": warm
// off-white paper), with GoodNotes and Noteful as the reference: thin light
// gray-blue rules and dots, a soft red margin. Page files hold opaque colors.
constexpr double kRuleWidth = 0.6;
constexpr double kDotDiameter = 1.5;
constexpr Rgb kPaper{252, 250, 245}, kRule{201, 211, 224}, kMargin{232, 160, 160};

// Write units to pt.
constexpr double Pt(double units) { return units * 0.48; }

}  // namespace

Background MakeBackground(const RulingSpec &spec, double width, double height) {
  Background bg{.ruling = spec.ruling,
                .y_ruling = spec.ruling == Ruling::kBlank ? 0 : spec.y_ruling,
                .y_offset = spec.ruling == Ruling::kBlank ? 0 : spec.y_ruling,
                .x_ruling = spec.x_ruling,
                .margin_left = spec.margin_left,
                .fill = kPaper};
  if (spec.ruling == Ruling::kDotted) {
    RulingPath dots{.stroke = kRule, .stroke_width = kDotDiameter, .round_caps = true};
    for (double y = spec.y_ruling; y < height; y += spec.y_ruling) {
      for (double x = spec.x_ruling; x < width; x += spec.x_ruling) dots.d.push_back({{x, y}, {x, y}});
    }
    bg.lines.push_back(std::move(dots));
    return bg;
  }
  if (spec.ruling == Ruling::kBlank) return bg;
  RulingPath rows{.stroke = kRule, .stroke_width = kRuleWidth};
  for (double y = spec.y_ruling; y < height; y += spec.y_ruling) rows.d.push_back({{0, y}, {width, y}});
  bg.lines.push_back(std::move(rows));
  if (spec.x_ruling > 0) {
    RulingPath columns{.stroke = kRule, .stroke_width = kRuleWidth};
    for (double x = spec.x_ruling; x < width; x += spec.x_ruling) columns.d.push_back({{x, 0}, {x, height}});
    bg.lines.push_back(std::move(columns));
  }
  if (spec.margin_left > 0) {
    bg.lines.push_back({.d = {{{spec.margin_left, 0}, {spec.margin_left, height}}},
                        .stroke = kMargin,
                        .stroke_width = kRuleWidth});
  }
  return bg;
}

const std::vector<BuiltinTemplate> &BuiltinTemplates() {
  // Write rulingdialog.cpp predefRulings {x ruling, y ruling, left margin}.
  static const std::vector<BuiltinTemplate> templates = {
      {"blank", {Ruling::kBlank}},
      {"lined-wide", {Ruling::kLined, Pt(45), 0, Pt(100)}},
      {"lined-medium", {Ruling::kLined, Pt(40), 0, Pt(100)}},
      {"lined-narrow", {Ruling::kLined, Pt(35), 0, Pt(100)}},
      {"grid-coarse", {Ruling::kGrid, Pt(35), Pt(35), Pt(35)}},
      {"grid-medium", {Ruling::kGrid, Pt(30), Pt(30), Pt(30)}},
      {"grid-fine", {Ruling::kGrid, Pt(20), Pt(20), Pt(20)}},
      // Write has no dotted preset: the coarse grid's spacing, dots only.
      {"dotted", {Ruling::kDotted, Pt(35), Pt(35), 0}},
  };
  return templates;
}

std::optional<Document> BuiltinTemplateNotebook(const std::string &name, IdGenerator &ids) {
  for (const BuiltinTemplate &t : BuiltinTemplates()) {
    if (name != t.name) continue;
    Document document = NewNotebook(ids);
    document.notebook.title = name;
    document.notebook.template_name = name;
    Page page = *document.pages[0];
    page.background = MakeBackground(t.spec, page.width, page.height);
    document.pages = document.pages.set(0, immer::box<Page>(std::move(page)));
    return document;
  }
  return std::nullopt;
}

}  // namespace ink_engine
