// Tool settings: Notes/.pens.json through the C ABI, and strokes drawn with
// them (issue #25).
#include <catch2/catch_test_macros.hpp>

#include <string>
#include <vector>

#include "ink.h"
#include "support/session.h"

namespace {

std::string Text(const uint8_t *bytes, size_t size) {
  return {reinterpret_cast<const char *>(bytes), size};
}

// A read file, copied out of the engine's buffers.
struct Pens {
  InkToolSettings pen;
  InkToolSettings marker;
  InkToolSettings highlighter;
  std::vector<uint32_t> palette;
  std::vector<InkToolSettings> saved;
};

Pens Read(const std::string &json) {
  const InkPenFile *file = nullptr;
  REQUIRE(ink_pens_read(reinterpret_cast<const uint8_t *>(json.data()), json.size(), &file) == INK_OK);
  return {file->pen, file->marker, file->highlighter, {file->palette, file->palette + file->palette_count},
          {file->saved, file->saved + file->saved_count}};
}

std::string Write(const Pens &pens) {
  InkPenFile file{pens.pen,           pens.marker,       pens.highlighter,
                  pens.palette.data(),
                  pens.palette.size(), pens.saved.data(), pens.saved.size()};
  const uint8_t *json = nullptr;
  size_t size = 0;
  REQUIRE(ink_pens_write(&file, &json, &size) == INK_OK);
  return Text(json, size);
}

std::string Default() {
  const uint8_t *json = nullptr;
  size_t size = 0;
  REQUIRE(ink_pens_default(&json, &size) == INK_OK);
  return Text(json, size);
}

// The saved text of the notebook's first page.
std::string SavedPage(InkDocument *document) {
  const InkFile *files = nullptr;
  size_t count = 0;
  REQUIRE(ink_document_dirty_files(document, &files, &count) == INK_OK);
  for (size_t i = 0; i < count; ++i) {
    if (std::string(files[i].path) == "pages/0001.svg") return Text(files[i].bytes, files[i].size);
  }
  FAIL("pages/0001.svg is not dirty");
  return {};
}

// The opening tag of the stroke element at `index` (0 = first) in a page file.
std::string StrokeTag(const std::string &page, int index) {
  size_t at = 0;
  for (int i = 0; i <= index; ++i) {
    at = page.find("<path id=\"s-", at + 1);
    REQUIRE(at != std::string::npos);
  }
  return page.substr(at, page.find(" d=\"", at) - at);
}

void Draw(InkCanvas *canvas, double y, double ms) {
  InkPenSample line[] = {
      {.x = 100, .y = y, .time = ms, .pressure = 0.5f, .has = INK_HAS_PRESSURE, .id = 0,
       .tool = INK_TOOL_PEN, .phase = INK_PHASE_BEGIN},
      {.x = 200, .y = y, .time = ms + 50, .pressure = 0.5f, .has = INK_HAS_PRESSURE, .id = 1,
       .tool = INK_TOOL_PEN, .phase = INK_PHASE_END}};
  REQUIRE(ink_input(canvas, line, 2) == INK_OK);
}

}  // namespace

TEST_CASE("The default tool settings file has the FORMAT.md form") {
  std::string text = Default();
  CHECK(text == R"({
  "pen": {
    "brush": "pressure-pen",
    "brushVersion": 1,
    "color": "#1A1A1A",
    "opacity": 1,
    "size": 1.2,
    "modes": 0,
    "smoothingMs": 20
  },
  "marker": {
    "brush": "marker",
    "brushVersion": 1,
    "color": "#1A1A1A",
    "opacity": 1,
    "size": 1.2,
    "modes": 0,
    "smoothingMs": 20
  },
  "highlighter": {
    "brush": "highlighter",
    "brushVersion": 1,
    "color": "#FFE066",
    "opacity": 0.35,
    "size": 9.6,
    "modes": 0,
    "smoothingMs": 20
  },
  "palette": [
    "#1A1A1A",
    "#1F4FB5",
    "#D92D39",
    "#29955B",
    "#FFCF26"
  ],
  "saved": []
}
)");
  CHECK(Write(Read(text)) == text);
}

TEST_CASE("Edited settings, palette and saved pens read back unchanged") {
  Pens pens = Read(Default());
  pens.pen = {INK_BRUSH_PRESSURE_PEN, 0x2F6FEB, 0.6f, 1, 0, 20};
  pens.marker = {INK_BRUSH_MARKER, 0xD92D39, 3.25f, 1, 0, 20};
  pens.highlighter.opacity = 0.5f;
  pens.palette = {0x2F6FEB, 0xFFFFFF};
  pens.saved = {{INK_BRUSH_PRESSURE_PEN, 0xD92D39, 0.6f, 1, 0, 20}, {INK_BRUSH_HIGHLIGHTER, 0x3CBFAE, 12, 0.35f, 0, 20},
                {INK_BRUSH_MARKER, 0x29955B, 2, 1, 0, 20}};

  Pens back = Read(Write(pens));
  CHECK(back.pen.rgb == 0x2F6FEB);
  CHECK(back.pen.size == 0.6f);
  CHECK(back.marker.rgb == 0xD92D39);
  CHECK(back.marker.size == 3.25f);
  CHECK(back.highlighter.opacity == 0.5f);
  CHECK(back.palette == std::vector<uint32_t>{0x2F6FEB, 0xFFFFFF});
  REQUIRE(back.saved.size() == 3);
  CHECK(back.saved[0].rgb == 0xD92D39);
  CHECK(back.saved[1].brush == INK_BRUSH_HIGHLIGHTER);
  CHECK(back.saved[1].size == 12);
  CHECK(back.saved[2].brush == INK_BRUSH_MARKER);
}

TEST_CASE("A file without the FORMAT.md form gives a parse error") {
  auto tool = [](const std::string &name, const std::string &brush) {
    return R"(")" + name + R"(": {"brush": ")" + brush + R"(", "brushVersion": 1, "color": "#1A1A1A", "opacity": 1, "size": 1, "modes": 0, "smoothingMs": 20})";
  };
  auto file = [&](const std::string &pen, const std::string &marker) {
    return "{" + tool("pen", pen) + ", " + tool("marker", marker) + ", " + tool("highlighter", "highlighter") +
           R"(, "palette": [], "saved": []})";
  };
  for (std::string bad : {std::string(R"([{"id": "pen", "name": "Pen"}])"),
                          file("highlighter", "marker"), file("chalk", "marker"), file("marker", "marker"),
                          file("pressure-pen", "pressure-pen"),
                          "{" + tool("pen", "pressure-pen") + ", " + tool("highlighter", "highlighter") +
                              R"(, "palette": [], "saved": []})"}) {
    const InkPenFile *file = nullptr;
    CHECK(ink_pens_read(reinterpret_cast<const uint8_t *>(bad.data()), bad.size(), &file) == INK_ERROR_PARSE);
  }
}

TEST_CASE("Strokes keep their own brush, color and size after the settings change") {
  Pens pens = Read(Default());
  ink_test::Session session;

  InkToolSettings highlighter = pens.highlighter;
  REQUIRE(ink_canvas_set_tool(session.get(), &highlighter) == INK_OK);
  Draw(session.get(), 100, 0);
  InkToolSettings pen = pens.pen;
  REQUIRE(ink_canvas_set_tool(session.get(), &pen) == INK_OK);
  Draw(session.get(), 200, 1000);
  std::string before = SavedPage(session.document);
  REQUIRE(ink_document_mark_saved(session.document) == INK_OK);

  // The user edits the presets; the next stroke uses the edited marker.
  highlighter.rgb = 0x3FA35B;
  highlighter.size = 4;
  InkToolSettings marker = pens.marker;
  marker.rgb = 0xD6455D;
  marker.size = 2;
  REQUIRE(ink_canvas_set_tool(session.get(), &marker) == INK_OK);
  Draw(session.get(), 300, 2000);
  std::string after = SavedPage(session.document);

  // The highlighter goes under the ink, so it is the first stroke.
  std::string old_highlight = StrokeTag(before, 0), old_pen = StrokeTag(before, 1);
  CHECK(old_highlight.find(R"(fill="#FFE066" fill-opacity="0.35" mn:brush="highlighter")") !=
        std::string::npos);
  CHECK(old_highlight.find(R"(mn:size="9.6")") != std::string::npos);
  CHECK(old_pen.find(R"(fill="#1A1A1A" mn:brush="pressure-pen")") != std::string::npos);
  CHECK(old_pen.find(R"(mn:size="1.2")") != std::string::npos);
  CHECK(StrokeTag(after, 0) == old_highlight);
  CHECK(StrokeTag(after, 1) == old_pen);
  std::string edited = StrokeTag(after, 2);
  CHECK(edited.find(R"(fill="#D6455D" mn:brush="marker")") != std::string::npos);
  CHECK(edited.find(R"(mn:size="2")") != std::string::npos);
}
