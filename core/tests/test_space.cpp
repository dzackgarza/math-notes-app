// Insert space (issue #31): the vertical, horizontal and ruled tools and word
// reflow, against the cases recorded from Write (tests/fixtures/write), and
// the rules for fixed pages.
#include <catch2/catch_test_macros.hpp>

#include <algorithm>
#include <cmath>
#include <map>
#include <string>
#include <vector>

#include "document/pages.h"
#include "editor/canvas.h"
#include "support/session.h"
#include "support/write_fixture.h"

using namespace ink_engine;

namespace {

const std::string kWriteDir = INK_FIXTURE_DIR "/../../../tests/fixtures/write/";

// Replays a case on its page. Each stroke Write deleted is gone; every other
// stroke is on page 0 with Write's translation. With `until`, replays the
// lines before the first command of that name and checks the elements that
// Write numbers 0 to `count` - 1: the rest of the case must leave them as
// they are.
void CheckAgainstWrite(const std::string &name, const std::string &until = "", size_t count = 0) {
  auto trace = ink_test::ReadWriteTrace(kWriteDir + name + "/trace.txt", until);
  auto expected = ink_test::ReadWriteExpected(kWriteDir + name + "/expected.json");
  ink_test::Session canvas(
      ink_test::WithWritePage(ink_test::Session().doc(), ink_test::ReadWritePage(kWriteDir + name + "/trace.txt")));
  std::vector<std::string> drawn = ink_test::ReplayWriteTrace(canvas.get(), trace);

  REQUIRE(ListedPageCount(canvas.doc()) == 1);
  std::map<std::string, Transform> ours;
  auto add = [&](const Element &element) {
    const Stroke &stroke = std::get<Stroke>(element.value);
    ours[stroke.id] = stroke.transform;
  };
  for (const auto &element : canvas.doc().pages[0]->layers[0].elements) {
    if (const auto *link = std::get_if<Link>(&element->value)) {
      for (const auto &child : link->children) add(*child);
    } else {
      add(*element);
    }
  }
  if (until.empty()) {
    count = drawn.size();
    REQUIRE(count == expected.elements.size() + expected.deleted.size());
  }
  REQUIRE(count <= drawn.size());
  for (int id : expected.deleted) {
    if (size_t(id) >= count) continue;
    INFO("stroke " << id);
    CHECK(!ours.contains(drawn[id]));
  }
  for (const ink_test::WriteElement &element : expected.elements) {
    // A link has no translation of its own.
    if (size_t(element.id) >= count || drawn[element.id].empty()) continue;
    INFO("stroke " << element.id);
    REQUIRE(ours.contains(drawn[element.id]));
    const Transform &transform = ours[drawn[element.id]];
    CHECK(transform.IsTranslation());
    CHECK(std::abs(transform.e - element.transform.e) < 0.01);
    CHECK(std::abs(transform.f - element.transform.f) < 0.01);
  }
}

void PenInput(InkCanvas *canvas, InkPhase phase, Point at, double time) {
  InkPenSample s{.x = at.x, .y = at.y, .time = time, .pressure = 0.5f, .tool = INK_TOOL_PEN,
                 .phase = uint8_t(phase)};
  REQUIRE(ink_input(canvas, &s, 1) == INK_OK);
}

// A pen drag in steps of at most 10 pt.
void Drag(InkCanvas *canvas, Point from, Point to, double time, InkPhase last = INK_PHASE_END) {
  const int steps = std::max(2, int(std::ceil(std::hypot(to.x - from.x, to.y - from.y) / 10)));
  PenInput(canvas, INK_PHASE_BEGIN, from, time);
  for (int i = 1; i < steps; ++i)
    PenInput(canvas, INK_PHASE_MOVE, {from.x + (to.x - from.x) * i / steps, from.y + (to.y - from.y) * i / steps},
        time + 10.0 * i);
  PenInput(canvas, last, to, time + 10.0 * steps);
}

// The origin of listed page `index` in view coordinates, and its size.
Rect PageRect(InkDocument *document, size_t index) {
  double x, y, w, h;
  REQUIRE(ink_document_page_rect(document, index, &x, &y, &w, &h) == INK_OK);
  return {x, y, x + w, y + h};
}

bool Same(const Rect &a, const Rect &b) {
  return a.left == b.left && a.top == b.top && a.right == b.right && a.bottom == b.bottom;
}

// A notebook of `pages` blank pages with the marker selected.
struct Pages {
  explicit Pages(size_t pages) {
    for (size_t p = 1; p < pages; ++p) REQUIRE(ink_document_insert_page(session.document, p) == INK_OK);
    ink_test::SetTool(session.get(), INK_BRUSH_MARKER, 0x1A1A1A, 2);
  }
  // A horizontal stroke on `page` at page coordinates; returns its bounds.
  Rect Draw(size_t page, Point from, Point to) {
    const Rect rect = PageRect(session.document, page);
    time += 5000;
    Drag(session.get(), {rect.left + from.x, rect.top + from.y}, {rect.left + to.x, rect.top + to.y}, time);
    return ElementBounds(*Ink(page).back());
  }
  // A drag of the insert space tool `kind` on `page`, at page coordinates.
  void Space(InkSelector kind, size_t page, Point from, Point to, InkPhase last = INK_PHASE_END) {
    const Rect rect = PageRect(session.document, page);
    time += 5000;
    ink_canvas_set_selector(session.get(), kind, 1);
    Drag(session.get(), {rect.left + from.x, rect.top + from.y}, {rect.left + to.x, rect.top + to.y}, time, last);
  }
  const Elements &Ink(size_t page) const { return session.doc().pages[page]->layers[0].elements; }
  Rect Bounds(size_t page, size_t index) const { return ElementBounds(*Ink(page)[index]); }

  ink_test::Session session;
  double time = 0;
};

}  // namespace

TEST_CASE("The ink moves with the pen while the insert space drag is down; a cancel restores it") {
  Pages book(1);
  const Rect left = book.Draw(0, {100, 100}, {140, 100});
  const Rect right = book.Draw(0, {300, 100}, {340, 100});
  const Document before = book.session.doc();
  const size_t steps = book.session.document->history.size();
  Editor &editor = book.session.canvas->editor;

  book.Space(INK_SELECTOR_SPACE_RULED, 0, {200, 100}, {260, 100}, INK_PHASE_MOVE);
  // The pen is down: the shown page has the ink right of the pen 60 pt
  // further right, and the notebook has no change yet.
  const Elements &shown = editor.Shown().pages[0]->layers[0].elements;
  REQUIRE(shown.size() == 2);
  CHECK(Same(ElementBounds(*shown[0]), left));
  CHECK(std::abs(ElementBounds(*shown[1]).left - (right.left + 60)) < 1e-9);
  CHECK(std::abs(ElementBounds(*shown[1]).top - right.top) < 1e-9);
  CHECK(book.session.doc() == before);
  CHECK_FALSE(editor.Overlay().has_value());

  PenInput(book.session.get(), INK_PHASE_CANCEL, {0, 0}, book.time + 1000);
  CHECK(editor.Shown() == before);
  CHECK(book.session.doc() == before);
  CHECK(book.session.document->history.size() == steps);

  // The release makes one history step with what the drag showed.
  book.Space(INK_SELECTOR_SPACE_RULED, 0, {200, 100}, {260, 100});
  CHECK(book.session.document->history.size() == steps + 1);
  CHECK(Same(book.Bounds(0, 0), left));
  CHECK(std::abs(book.Bounds(0, 1).left - (right.left + 60)) < 1e-9);
  CHECK(editor.Shown() == book.session.doc());
}

TEST_CASE("Horizontal insert space moves the ink right of the pen and stops it at the page edge") {
  Pages book(1);
  const double width = book.session.doc().pages[0]->width;
  const Rect left = book.Draw(0, {100, 300}, {140, 300});
  const Rect right = book.Draw(0, {300, 500}, {340, 500});

  book.Space(INK_SELECTOR_SPACE_HORIZONTAL, 0, {200, 400}, {280, 400});
  CHECK(Same(book.Bounds(0, 0), left));
  CHECK(std::abs(book.Bounds(0, 1).left - (right.left + 80)) < 1e-9);

  int32_t undone = 0, page = -1;
  REQUIRE(ink_undo(book.session.document, &undone, &page) == INK_OK);
  book.Space(INK_SELECTOR_SPACE_HORIZONTAL, 0, {200, 400}, {width - 5, 400});
  CHECK(std::abs(book.Bounds(0, 1).right - width) < 1e-9);
  CHECK(ListedPageCount(book.session.doc()) == 1);
}

TEST_CASE("Insert space with room on the page changes no other page") {
  Pages book(2);
  const Rect above = book.Draw(0, {100, 100}, {200, 100});
  const Rect below = book.Draw(0, {100, 300}, {200, 300});
  book.Draw(1, {100, 100}, {200, 100});
  const immer::box<Page> second = book.session.doc().pages[1];

  book.Space(INK_SELECTOR_SPACE_VERTICAL, 0, {300, 200}, {300, 350});
  CHECK(Same(book.Bounds(0, 0), above));
  CHECK(std::abs(book.Bounds(0, 1).top - (below.top + 150)) < 1e-9);
  CHECK(book.session.doc().pages[1] == second);
}

TEST_CASE("Vertical insert space puts the ink that passes the page bottom on the next page, above that page's ink") {
  Pages book(2);
  const double height = book.session.doc().pages[0]->height;
  const Rect pushed = book.Draw(0, {100, 700}, {200, 720});
  const Rect next = book.Draw(1, {100, 100}, {200, 100});
  const std::string pushed_id = std::get<Stroke>(book.Ink(0)[0]->value).id;
  const size_t steps = book.session.document->history.size();

  book.Space(INK_SELECTOR_SPACE_VERTICAL, 0, {300, 600}, {300, 800});
  CHECK(book.Ink(0).empty());
  REQUIRE(book.Ink(1).size() == 2);
  // The pushed ink is 200 pt lower in the run of pages.
  CHECK(std::get<Stroke>(book.Ink(1)[1]->value).id == pushed_id);
  CHECK(std::abs(book.Bounds(1, 1).top - (pushed.top + 200 - height)) < 1e-9);
  CHECK(std::abs(book.Bounds(1, 1).left - pushed.left) < 1e-9);
  // The ink of the next page moved down by the depth the pushed ink takes.
  CHECK(std::abs(book.Bounds(1, 0).top - (next.top + book.Bounds(1, 1).bottom)) < 1e-9);
  CHECK(ListedPageCount(book.session.doc()) == 2);
  CHECK(book.session.document->history.size() == steps + 1);
}

TEST_CASE("Ruled insert space moves whole lines past the last page onto a new page; one undo restores the notebook") {
  Pages book(1);
  const Rect kept = book.Draw(0, {100, 300}, {200, 300});
  const Rect pushed = book.Draw(0, {100, 800}, {200, 800});
  const Document before = book.session.doc();
  const size_t steps = book.session.document->history.size();

  // The pen-down is on an empty line: the lines below it move, 5 lines for
  // a drag of 96 pt on the 19.2 pt lines of a blank page.
  book.Space(INK_SELECTOR_SPACE_RULED, 0, {300, 700}, {300, 796});
  REQUIRE(ListedPageCount(book.session.doc()) == 2);
  REQUIRE(book.Ink(0).size() == 1);
  CHECK(Same(book.Bounds(0, 0), kept));
  REQUIRE(book.Ink(1).size() == 1);
  // Line 40 of the 42 lines of page 1 became line 3 of page 2.
  const double first_line = std::fmod(700 - 9.6, 19.2);
  CHECK(std::abs(book.Bounds(1, 0).top - (pushed.top + (5 - 42) * 19.2)) < 1e-9);
  CHECK(int(std::floor((book.Bounds(1, 0).top - first_line) / 19.2)) == 3);
  CHECK(book.session.document->history.size() == steps + 1);

  int32_t undone = 0, page = -1;
  REQUIRE(ink_undo(book.session.document, &undone, &page) == INK_OK);
  CHECK(book.session.doc() == before);
}

TEST_CASE("A word that reflows past the last line of a page starts the first line of the next page") {
  Pages book(2);
  // Three words on the last whole line of page 1, and a word on the first
  // line of page 2. The lines are 19.2 pt apart and the first starts at 18.2.
  const Rect first = book.Draw(0, {100, 815}, {140, 815});
  const Rect second = book.Draw(0, {300, 815}, {340, 815});
  const Rect third = book.Draw(0, {500, 815}, {540, 815});
  const Rect next = book.Draw(1, {300, 27.8}, {340, 27.8});
  const size_t steps = book.session.document->history.size();

  // 80 pt of space after the first word puts the third past the right edge.
  book.Space(INK_SELECTOR_SPACE_RULED, 0, {200, 815}, {280, 815});
  REQUIRE(book.Ink(0).size() == 2);
  CHECK(Same(book.Bounds(0, 0), first));
  CHECK(std::abs(book.Bounds(0, 1).left - (second.left + 80)) < 1e-9);
  REQUIRE(book.Ink(1).size() == 2);
  // The third word is on the first line of page 2, at the start of the line
  // as on a line of its own page (0.3 of a line from the left limit).
  CHECK(std::abs(book.Bounds(1, 1).left - 0.3 * 19.2) < 1e-9);
  CHECK(std::abs(book.Bounds(1, 1).top - (third.top - 815 + 27.8)) < 1e-9);
  // The ink of page 2 is one line lower.
  CHECK(std::abs(book.Bounds(1, 0).left - next.left) < 1e-9);
  CHECK(std::abs(book.Bounds(1, 0).top - (next.top + 19.2)) < 1e-9);
  CHECK(ListedPageCount(book.session.doc()) == 2);
  CHECK(book.session.document->history.size() == steps + 1);
}

TEST_CASE("Ruled insert space on a blank page moves the rest of the line as Write does") {
  CheckAgainstWrite("insspace-virtual-ruling");
}

TEST_CASE("Ruled insert space dragged left deletes the swept strokes and closes the gap") {
  CheckAgainstWrite("insspace-negative-erase");
}

TEST_CASE("Ruled insert space reflows the words of one column and leaves the other column") {
  CheckAgainstWrite("reflow-column-divider");
}

TEST_CASE("Ruled insert space reflows words to the next lines; vertical insert space moves the ink below") {
  CheckAgainstWrite("upstream-test7");
}

TEST_CASE("Ruled insert space reflows a column that a slanted divider bounds; the second column stays") {
  // The case goes on to draw more strokes, and to erase them.
  CheckAgainstWrite("upstream-test11", "pen", 129);
}

TEST_CASE("Ruled insert space reflows words that were not drawn from left to right in their order on the line") {
  // The case goes on to paste a figure from Write's clipboard.
  CheckAgainstWrite("upstream-test15", "clipsvg", 28);
}
