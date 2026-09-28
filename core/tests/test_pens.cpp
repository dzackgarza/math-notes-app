// Pen presets: Notes/.pens.json through the C ABI, and strokes drawn with them
// (issue #25).
#include <catch2/catch_test_macros.hpp>

#include <string>
#include <vector>

#include "ink.h"
#include "support/session.h"

namespace {

std::string Text(const uint8_t *bytes, size_t size) {
  return {reinterpret_cast<const char *>(bytes), size};
}

std::vector<InkPen> Read(const std::string &json) {
  const InkPen *pens = nullptr;
  size_t count = 0;
  REQUIRE(ink_pens_read(reinterpret_cast<const uint8_t *>(json.data()), json.size(), &pens, &count) ==
          INK_OK);
  return {pens, pens + count};
}

std::string Write(const std::vector<InkPen> &pens) {
  const uint8_t *json = nullptr;
  size_t size = 0;
  REQUIRE(ink_pens_write(pens.data(), pens.size(), &json, &size) == INK_OK);
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

TEST_CASE("The default pen file lists the three presets in FORMAT.md key order") {
  const uint8_t *json = nullptr;
  size_t size = 0;
  REQUIRE(ink_pens_default(&json, &size) == INK_OK);
  std::string text = Text(json, size);
  CHECK(text == R"([
  {
    "id": "pen",
    "name": "Pen",
    "brush": "pressure-pen",
    "brushVersion": 1,
    "color": "#1A1A1A",
    "opacity": 1,
    "size": 1.2
  },
  {
    "id": "thick-pen",
    "name": "Thick pen",
    "brush": "marker",
    "brushVersion": 1,
    "color": "#1A1A1A",
    "opacity": 1,
    "size": 2.4
  },
  {
    "id": "highlighter",
    "name": "Highlighter",
    "brush": "highlighter",
    "brushVersion": 1,
    "color": "#FFE066",
    "opacity": 0.35,
    "size": 9.6
  }
]
)");
  CHECK(Write(Read(text)) == text);
}

TEST_CASE("An edited preset is written with its new brush, color and size") {
  const uint8_t *json = nullptr;
  size_t size = 0;
  REQUIRE(ink_pens_default(&json, &size) == INK_OK);
  std::vector<InkPen> pens = Read(Text(json, size));
  pens[1].tool = {INK_BRUSH_MARKER, 0x2F6FEB, 3.25f, 1};

  std::vector<InkPen> back = Read(Write(pens));
  REQUIRE(back.size() == 3);
  CHECK(std::string(back[1].id) == "thick-pen");
  CHECK(back[1].tool.brush == INK_BRUSH_MARKER);
  CHECK(back[1].tool.rgb == 0x2F6FEB);
  CHECK(back[1].tool.size == 3.25f);
  CHECK(back[2].tool.opacity == 0.35f);
}

TEST_CASE("A file that is not a pen list gives a parse error") {
  std::string bad = R"([{"id": "p", "name": "P"}])";
  const InkPen *pens = nullptr;
  size_t count = 0;
  CHECK(ink_pens_read(reinterpret_cast<const uint8_t *>(bad.data()), bad.size(), &pens, &count) ==
        INK_ERROR_PARSE);
}

TEST_CASE("Strokes keep their own brush, color and size after their preset changes") {
  const uint8_t *json = nullptr;
  size_t size = 0;
  REQUIRE(ink_pens_default(&json, &size) == INK_OK);
  std::vector<InkPen> pens = Read(Text(json, size));
  ink_test::Session session;

  InkToolSettings highlighter = pens[4].tool;
  REQUIRE(ink_canvas_set_tool(session.get(), &highlighter) == INK_OK);
  Draw(session.get(), 100, 0);
  InkToolSettings blue = pens[1].tool;
  REQUIRE(ink_canvas_set_tool(session.get(), &blue) == INK_OK);
  Draw(session.get(), 200, 1000);
  std::string before = SavedPage(session.document);
  REQUIRE(ink_document_mark_saved(session.document) == INK_OK);

  // The user edits both presets; the next stroke uses the edited blue pen.
  highlighter.rgb = 0x3FA35B;
  highlighter.size = 4;
  blue = {INK_BRUSH_MARKER, 0xD6455D, 2, 1};
  REQUIRE(ink_canvas_set_tool(session.get(), &blue) == INK_OK);
  Draw(session.get(), 300, 2000);
  std::string after = SavedPage(session.document);

  // The highlighter goes under the ink, so it is the first stroke.
  std::string old_highlight = StrokeTag(before, 0), old_blue = StrokeTag(before, 1);
  CHECK(old_highlight.find(R"(fill="#FFE066" fill-opacity="0.35" mn:brush="highlighter")") !=
        std::string::npos);
  CHECK(old_highlight.find(R"(mn:size="9.6")") != std::string::npos);
  CHECK(old_blue.find(R"(fill="#1F4FB5" mn:brush="pressure-pen")") != std::string::npos);
  CHECK(old_blue.find(R"(mn:size="1.2")") != std::string::npos);
  CHECK(StrokeTag(after, 0) == old_highlight);
  CHECK(StrokeTag(after, 1) == old_blue);
  std::string edited = StrokeTag(after, 2);
  CHECK(edited.find(R"(fill="#D6455D" mn:brush="marker")") != std::string::npos);
  CHECK(edited.find(R"(mn:size="2")") != std::string::npos);
}
