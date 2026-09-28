// Undo and redo over the document history (issue #22).
#include <catch2/catch_test_macros.hpp>

#include <cmath>
#include <random>
#include <set>
#include <string>

#include "document/pages.h"
#include "format/notebook.h"
#include "ink.h"
#include "layout/layout.h"
#include "support/session.h"

using namespace ink_engine;

namespace {

void DrawStroke(InkCanvas *canvas, double x, double y) {
  InkPenSample samples[] = {
      {.x = x, .y = y, .time = 0, .tool = INK_TOOL_PEN, .phase = INK_PHASE_BEGIN},
      {.x = x + 20, .y = y + 5, .time = 20, .id = 1, .tool = INK_TOOL_PEN, .phase = INK_PHASE_MOVE},
      {.x = x + 40, .y = y, .time = 40, .id = 2, .tool = INK_TOOL_PEN, .phase = INK_PHASE_END}};
  REQUIRE(ink_input(canvas, samples, 3) == INK_OK);
}

// A handwriting-sized stroke: 167 samples, as the recorded strokes of the
// 400-stroke page measured in #3.
void DrawLongStroke(InkCanvas *canvas, double x, double y) {
  std::vector<InkPenSample> samples;
  for (uint32_t i = 0; i < 167; ++i) {
    double t = i / 166.0;
    InkPhase phase = i == 0 ? INK_PHASE_BEGIN : i == 166 ? INK_PHASE_END : INK_PHASE_MOVE;
    samples.push_back({.x = x + 20 * t, .y = y + 8 * std::sin(12 * t), .time = 4.0 * i,
                       .pressure = 0.5f, .has = INK_HAS_PRESSURE, .id = i, .tool = INK_TOOL_PEN,
                       .phase = uint8_t(phase)});
  }
  REQUIRE(ink_input(canvas, samples.data(), samples.size()) == INK_OK);
}

// The strokes of a page's first layer, as a history step: an edit the
// erasers and the selection make (issues #23, #24).
void EditStrokes(DocumentHistory &history, size_t page_index,
                 const std::function<void(Elements &)> &edit) {
  Document next = history.current();
  Page page = *next.pages[page_index];
  edit(page.layers[0].elements);
  next.pages = next.pages.set(page_index, immer::box<Page>(std::move(page)));
  history.Push(std::move(next));
}

std::map<std::string, std::string> Written(InkDocument *document) {
  const InkFile *files = nullptr;
  size_t count = 0;
  REQUIRE(ink_document_dirty_files(document, &files, &count) == INK_OK);
  std::map<std::string, std::string> out;
  for (size_t i = 0; i < count; ++i) {
    REQUIRE(files[i].kind == INK_FILE_WRITE);
    out[files[i].path] = std::string(reinterpret_cast<const char *>(files[i].bytes), files[i].size);
  }
  return out;
}

// View point at (x, y) pt on listed page `page` (identity view).
std::pair<double, double> OnPage(const Document &document, size_t page, double x, double y) {
  PagePlacement p = LayoutPages(document)[page];
  return {p.x + x, p.y + y};
}

}  // namespace

TEST_CASE("Undoing 1000 random edits gives the start value; redoing them the end value") {
  ink_test::Session session(11);
  DocumentHistory &history = session.document->history;
  std::mt19937_64 random(5);
  auto pick = [&](size_t n) { return size_t(random() % n); };
  const Document start = history.current();
  size_t steps = 0;
  for (int i = 0; i < 1000; ++i) {
    size_t pages = ListedPageCount(history.current());
    size_t page = pick(pages);
    size_t strokes = history.current().pages[page]->layers[0].elements.size();
    switch (pick(5)) {
      case 0: {  // stroke add
        auto [x, y] = OnPage(history.current(), page, 50 + pick(400), 50 + pick(700));
        DrawStroke(session.get(), x, y);
        break;
      }
      case 1:  // erase
        if (strokes == 0) continue;
        EditStrokes(history, page, [&](Elements &e) { e = e.erase(pick(strokes)); });
        break;
      case 2:  // move
        if (strokes == 0) continue;
        EditStrokes(history, page, [&](Elements &e) {
          size_t k = pick(strokes);
          Element moved = *e[k];
          std::get<Stroke>(moved.value).transform.e += 10;
          e = e.set(k, immer::box<Element>(std::move(moved)));
        });
        break;
      case 3:  // page insert
        REQUIRE(ink_document_insert_page(session.document, pick(pages + 1)) == INK_OK);
        break;
      default:  // page delete
        if (pages == 1) continue;
        REQUIRE(ink_document_delete_page(session.document, page) == INK_OK);
    }
    ++steps;
  }
  REQUIRE(history.size() == steps + 1);
  const Document end = history.current();
  int32_t moved = 0, shown = 0;
  for (size_t i = 0; i < steps; ++i) REQUIRE(ink_undo(session.document, &moved, &shown) == INK_OK);
  CHECK(history.current() == start);
  ink_undo(session.document, &moved, &shown);
  CHECK(moved == 0);
  for (size_t i = 0; i < steps; ++i) ink_redo(session.document, &moved, &shown);
  CHECK(history.current() == end);
}

TEST_CASE("Undoing a stroke on page 7 shows page 7 and saves only its file") {
  ink_test::Session session;
  for (size_t i = 1; i < 10; ++i) ink_document_insert_page(session.document, i);
  ink_document_mark_saved(session.document);
  auto [x, y] = OnPage(session.doc(), 6, 100, 100);
  DrawStroke(session.get(), x, y);
  ink_document_mark_saved(session.document);

  int32_t moved = 0, page = 0;
  REQUIRE(ink_undo(session.document, &moved, &page) == INK_OK);
  CHECK(moved == 1);
  CHECK(page == 6);
  auto written = Written(session.document);
  REQUIRE(written.size() == 1);
  CHECK(written.contains("pages/0007.svg"));
  CHECK(written.at("pages/0007.svg") == AllFiles(session.doc()).at("pages/0007.svg"));

  ink_document_set_page_size(session.document, INK_PAGE_LETTER, INK_PORTRAIT, 0, 0);
  ink_undo(session.document, &moved, &page);
  CHECK(page == -1);  // a notebook setting, on no page
}

TEST_CASE("1000 stroke additions keep the history under twice the page plus the new strokes") {
  // The unique values the history holds: element boxes, page boxes, and the
  // element vectors' path copies (immer shares the rest). A path copy is at
  // most one 32-slot node per level of the vector's radix tree.
  auto element_bytes = [](const Element &e) {
    const Stroke &s = std::get<Stroke>(e.value);
    size_t points = 0;
    for (const Polyline &p : s.outline) points += p.size();
    return sizeof(Element) + points * sizeof(Point) + s.samples.size() * sizeof(Sample);
  };
  ink_test::Session session;
  DocumentHistory &history = session.document->history;
  for (int i = 0; i < 400; ++i) DrawLongStroke(session.get(), 20 + i % 20 * 25, 20 + i / 20 * 35);
  history.Reset(history.current());  // a loaded 400-stroke page
  size_t page_bytes = 0;
  for (const auto &e : history.current().pages[0]->layers[0].elements) page_bytes += element_bytes(*e);

  size_t added_bytes = 0;
  for (int i = 0; i < 1000; ++i) {
    DrawLongStroke(session.get(), 20 + i % 20 * 25, 740 + i % 3 * 20);
    added_bytes += element_bytes(*history.current().pages[0]->layers[0].elements.back());
  }
  REQUIRE(history.size() == 1001);

  std::set<const void *> seen;
  size_t history_bytes = 0;
  for (const Document &value : history.values()) {
    const auto &page = value.pages[0];
    if (seen.insert(&*page).second) history_bytes += sizeof(Page);
    const Elements &elements = page->layers[0].elements;
    size_t depth = 1;
    for (size_t n = elements.size(); n > 32; n /= 32) ++depth;
    history_bytes += depth * 32 * sizeof(void *);
    for (const auto &e : elements) {
      if (seen.insert(&*e).second) history_bytes += element_bytes(*e);
    }
  }
  INFO("page " << page_bytes << " B, added " << added_bytes << " B, history " << history_bytes << " B");
  CHECK(history_bytes < 2 * page_bytes + added_bytes);
}
