// The stroke eraser and the free eraser (issue #23), against the eraser cases
// recorded from Write (tests/fixtures/write: stroke-erase, free-erase,
// free-erase-document).
#include <catch2/catch_test_macros.hpp>

#include <algorithm>
#include <cmath>
#include <map>
#include <set>
#include <string>
#include <vector>

#include "editor/canvas.h"
#include "editor/erase.h"
#include "strokes/outline.h"
#include "support/session.h"
#include "support/write_fixture.h"

using namespace ink_engine;

namespace {

const std::string kWriteDir = INK_FIXTURE_DIR "/../../../tests/fixtures/write/";

struct Box {
  double left = 1e300, top = 1e300, right = -1e300, bottom = -1e300;
  void Add(Point p) {
    left = std::min(left, p.x), right = std::max(right, p.x);
    top = std::min(top, p.y), bottom = std::max(bottom, p.y);
  }
};

const Elements &Layer0(const Document &document) { return document.pages[0]->layers[0].elements; }

std::vector<Stroke> Strokes(const Document &document) {
  std::vector<Stroke> strokes;
  for (const auto &box : Layer0(document)) strokes.push_back(std::get<Stroke>(box->value));
  return strokes;
}

// A pen or eraser gesture in view coordinates, one ink_input call per sample.
void Gesture(InkCanvas *canvas, std::vector<Point> points, double t0, uint32_t buttons = 0) {
  for (size_t i = 0; i < points.size(); ++i) {
    InkPhase phase = i == 0 ? INK_PHASE_BEGIN : i + 1 == points.size() ? INK_PHASE_END : INK_PHASE_MOVE;
    InkPenSample s{.x = points[i].x, .y = points[i].y, .time = t0 + 10.0 * i, .pressure = 0.5f,
                   .buttons = buttons, .tool = INK_TOOL_PEN, .phase = uint8_t(phase)};
    REQUIRE(ink_input(canvas, &s, 1) == INK_OK);
  }
}

std::vector<Point> Line(Point a, Point b, int n) {
  std::vector<Point> points;
  for (int i = 0; i <= n; ++i) points.push_back({a.x + (b.x - a.x) * i / n, a.y + (b.y - a.y) * i / n});
  return points;
}

std::string PageBytes(InkDocument *document) {
  const InkFile *files = nullptr;
  size_t count = 0;
  REQUIRE(ink_document_dirty_files(document, &files, &count) == INK_OK);
  for (size_t i = 0; i < count; ++i) {
    if (std::string(files[i].path) == "pages/0001.svg") {
      return std::string(reinterpret_cast<const char *>(files[i].bytes), files[i].size);
    }
  }
  FAIL("page 1 is not dirty");
  return {};
}

// The distance from p to the boundary of the rectangle [x0, x1] × [y0, y1].
double ToRectEdge(Point p, double x0, double y0, double x1, double y1) {
  double dx = std::max({x0 - p.x, 0.0, p.x - x1}), dy = std::max({y0 - p.y, 0.0, p.y - y1});
  if (dx > 0 || dy > 0) return std::hypot(dx, dy);
  return std::min({p.x - x0, x1 - p.x, p.y - y0, y1 - p.y});
}


Document ProtectedLayerDocument() {
  ink_test::Session source;
  ink_test::SetTool(source.get(), INK_BRUSH_MARKER, 0x1A1A1A, 2);
  Gesture(source.get(), Line({100, 100}, {300, 100}, 10), 0);
  REQUIRE(ink_document_add_layer(source.document, "Hidden") == INK_OK);
  REQUIRE(ink_canvas_set_layer(source.get(), 1) == INK_OK);
  Gesture(source.get(), Line({100, 200}, {300, 200}, 10), 200);
  REQUIRE(ink_document_add_layer(source.document, "Locked") == INK_OK);
  REQUIRE(ink_canvas_set_layer(source.get(), 2) == INK_OK);
  Gesture(source.get(), Line({100, 300}, {300, 300}, 10), 400);
  REQUIRE(ink_document_set_layer(source.document, 1, "Hidden", 1, 0) == INK_OK);
  REQUIRE(ink_document_set_layer(source.document, 2, "Locked", 0, 1) == INK_OK);
  return source.doc();
}

}  // namespace

TEST_CASE("The stroke eraser deletes the strokes Write deletes") {
  auto trace = ink_test::ReadWriteTrace(kWriteDir + "stroke-erase/trace.txt");
  auto expected = ink_test::ReadWriteExpected(kWriteDir + "stroke-erase/expected.json");
  ink_test::Session canvas;
  std::vector<std::string> drawn = ink_test::ReplayWriteTrace(canvas.get(), trace);

  std::set<std::string> present;
  for (const Stroke &s : Strokes(canvas.doc())) present.insert(s.id);
  std::set<int> deleted;
  for (size_t i = 0; i < drawn.size(); ++i) {
    if (!present.contains(drawn[i])) deleted.insert(int(i));
  }
  CHECK(deleted == expected.deleted);
  // Three erase gestures after the drawn strokes; the one that hits nothing adds no step.
  CHECK(canvas.document->history.size() == 1 + drawn.size() + 2);
}

TEST_CASE("The ruled eraser deletes the strokes Write deletes") {
  const std::string trace_file = kWriteDir + "ruled-erase-greedy/trace.txt";
  auto trace = ink_test::ReadWriteTrace(trace_file);
  auto expected = ink_test::ReadWriteExpected(kWriteDir + "ruled-erase-greedy/expected.json");
  ink_test::Session canvas(
      ink_test::WithWritePage(ink_test::Session().doc(), ink_test::ReadWritePage(trace_file)));
  std::vector<std::string> drawn = ink_test::ReplayWriteTrace(canvas.get(), trace);

  std::set<std::string> present;
  for (const Stroke &s : Strokes(canvas.doc())) present.insert(s.id);
  std::set<int> deleted;
  for (size_t i = 0; i < drawn.size(); ++i) {
    if (!present.contains(drawn[i])) deleted.insert(int(i));
  }
  CHECK(deleted == expected.deleted);
  // The erase gesture is one step.
  CHECK(canvas.document->history.size() == 1 + drawn.size() + 1);
}

TEST_CASE("The free eraser leaves Write's pieces") {
  for (std::string name : {"free-erase", "free-erase-document"}) {
    INFO(name);
    auto trace = ink_test::ReadWriteTrace(kWriteDir + name + "/trace.txt");
    auto expected = ink_test::ReadWriteExpected(kWriteDir + name + "/expected.json");
    std::vector<std::vector<Point>> input;
    if (name == "free-erase-document") input = ink_test::ReadWriteDocument(kWriteDir + name + "/input.html");
    ink_test::Session canvas(ink_test::WithStrokes(ink_test::Session().doc(), input));
    std::vector<std::string> originals;
    for (const Stroke &s : Strokes(canvas.doc())) originals.push_back(s.id);
    std::vector<std::string> drawn = ink_test::ReplayWriteTrace(canvas.get(), trace);
    originals.insert(originals.end(), drawn.begin(), drawn.end());

    // Write numbers the original strokes 0..n-1 in order; pieces get later ids.
    std::set<int> kept_originals, write_kept_originals;
    std::vector<Box> pieces, write_pieces;
    for (const Stroke &s : Strokes(canvas.doc())) {
      auto at = std::find(originals.begin(), originals.end(), s.id);
      if (at != originals.end()) {
        kept_originals.insert(int(at - originals.begin()));
        continue;
      }
      Box box;
      for (Point p : PagePath(s)) box.Add(p);
      pieces.push_back(box);
      // A piece's outline is the stroke of its brush and samples, built here
      // from the samples as google/ink inputs.
      ink::StrokeInputBatch inputs;
      for (const Sample &sample : s.samples) {
        REQUIRE(inputs.Append({.tool_type = ink::StrokeInput::ToolType::kStylus,
                               .position = {float(sample.x), float(sample.y)},
                               .elapsed_time = ink::Duration32::Millis(float(sample.t))})
                    .ok());
      }
      ink::Stroke direct(MakeBrush({.brush = INK_BRUSH_MARKER, .color = {0, 0, 0}, .size = 0.48f}), inputs);
      CHECK(s.outline == StrokeOutline(direct.GetShape()));
    }
    for (const auto &e : expected.elements) {
      if (e.id < int(originals.size())) {
        write_kept_originals.insert(e.id);
        continue;
      }
      REQUIRE(e.pen_points.size() == 1);
      Box box;
      for (Point p : e.pen_points[0]) box.Add(p);
      write_pieces.push_back(box);
    }
    CHECK(kept_originals == write_kept_originals);
    REQUIRE(pieces.size() == write_pieces.size());
    auto order = [](const Box &a, const Box &b) {
      return std::lround(a.top) != std::lround(b.top) ? a.top < b.top : a.left < b.left;
    };
    std::sort(pieces.begin(), pieces.end(), order);
    std::sort(write_pieces.begin(), write_pieces.end(), order);
    for (size_t i = 0; i < pieces.size(); ++i) {
      INFO("piece " << i << " at " << write_pieces[i].left << ", " << write_pieces[i].top);
      CHECK(std::abs(pieces[i].left - write_pieces[i].left) <= 1);
      CHECK(std::abs(pieces[i].top - write_pieces[i].top) <= 1);
      CHECK(std::abs(pieces[i].right - write_pieces[i].right) <= 1);
      CHECK(std::abs(pieces[i].bottom - write_pieces[i].bottom) <= 1);
    }
  }
}

TEST_CASE("A free-erase gesture is one step; undoing it writes back the original bytes") {
  ink_test::Session canvas;
  ink_test::SetTool(canvas.get(), INK_BRUSH_PRESSURE_PEN, 0x1F4FD1, 2);
  std::vector<InkPenSample> stroke;
  for (uint32_t i = 0; i <= 40; ++i) {
    InkPhase phase = i == 0 ? INK_PHASE_BEGIN : i == 40 ? INK_PHASE_END : INK_PHASE_MOVE;
    stroke.push_back({.x = 100 + 5.0 * i, .y = 200 + 10 * std::sin(i / 4.0), .time = 8.0 * i,
                      .pressure = 0.3f + 0.01f * i, .altitude = 1.0f, .azimuth = 0.5f,
                      .has = INK_HAS_PRESSURE | INK_HAS_ALTITUDE | INK_HAS_AZIMUTH, .id = i,
                      .tool = INK_TOOL_PEN, .phase = uint8_t(phase)});
  }
  REQUIRE(ink_input(canvas.get(), stroke.data(), stroke.size()) == INK_OK);
  std::string original = PageBytes(canvas.document);
  REQUIRE(ink_document_mark_saved(canvas.document) == INK_OK);
  const Stroke before = Strokes(canvas.doc()).at(0);

  ink_canvas_set_eraser(canvas.get(), INK_ERASER_FREE, 1);
  size_t steps = canvas.document->history.size();
  Gesture(canvas.get(), Line({200, 150}, {200, 250}, 10), 1000);
  CHECK(canvas.document->history.size() == steps + 1);
  std::vector<Stroke> pieces = Strokes(canvas.doc());
  REQUIRE(pieces.size() == 2);
  for (const Stroke &piece : pieces) {
    CHECK(piece.time == before.time);
    CHECK(piece.brush == before.brush);
    CHECK(piece.channels == before.channels);
  }
  // The cut is the eraser's width: 7 view units on each side of x = 200.
  CHECK(std::abs(pieces[0].samples.back().x - 193) < 1e-6);
  CHECK(std::abs(pieces[1].samples.front().x - 207) < 1e-6);
  CHECK(PageBytes(canvas.document) != original);
  REQUIRE(ink_document_mark_saved(canvas.document) == INK_OK);

  int32_t moved = 0, page = -1;
  REQUIRE(ink_undo(canvas.document, &moved, &page) == INK_OK);
  CHECK(moved == 1);
  CHECK(PageBytes(canvas.document) == original);
}

TEST_CASE("Hit strokes hide during a stroke-erase gesture and go on release") {
  ink_test::Session canvas;
  ink_test::SetTool(canvas.get(), INK_BRUSH_MARKER, 0x1A1A1A, 2);
  Gesture(canvas.get(), Line({100, 100}, {300, 100}, 10), 0);
  Gesture(canvas.get(), Line({100, 200}, {300, 200}, 10), 200);
  size_t steps = canvas.document->history.size();

  // The pen's eraser end (buttons bit 32) erases with the eraser tool off.
  std::vector<Point> path = Line({200, 50}, {200, 150}, 10);
  for (size_t i = 0; i + 1 < path.size(); ++i) {
    InkPenSample s{.x = path[i].x, .y = path[i].y, .time = 500.0 + i, .buttons = 32,
                   .tool = INK_TOOL_PEN, .phase = uint8_t(i ? INK_PHASE_MOVE : INK_PHASE_BEGIN)};
    ink_input(canvas.get(), &s, 1);
  }
  CHECK(Layer0(canvas.canvas->editor.Shown()).size() == 1);
  CHECK(Layer0(canvas.doc()).size() == 2);
  InkPenSample end{.x = 200, .y = 150, .time = 520, .buttons = 32, .tool = INK_TOOL_PEN,
                   .phase = INK_PHASE_END};
  ink_input(canvas.get(), &end, 1);
  CHECK(canvas.document->history.size() == steps + 1);
  std::vector<Stroke> left = Strokes(canvas.doc());
  REQUIRE(left.size() == 1);
  CHECK(left[0].samples.front().y == 200);
}

TEST_CASE("The erasers act on shapes") {
  // A 2 pt red rectangle from (100, 300) to (300, 400).
  Shape rect{.id = "s-rectangle00", .kind = ShapeKind::kRect, .stroke = {214, 69, 93},
             .stroke_width = 2, .points = {{100, 300}, {200, 100}}};
  Document document = ink_test::Session().doc();
  Page page = *document.pages[0];
  page.layers[0].elements = page.layers[0].elements.push_back(immer::box<Element>(Element{rect}));
  document.pages = document.pages.set(0, immer::box<Page>(std::move(page)));

  SECTION("the stroke eraser removes a shape whole") {
    ink_test::Session canvas(document);
    ink_canvas_set_eraser(canvas.get(), INK_ERASER_STROKE, 1);
    Gesture(canvas.get(), Line({150, 280}, {150, 320}, 4), 0);
    CHECK(Layer0(canvas.doc()).empty());
  }

  SECTION("the free eraser turns a shape into pen strokes along it, then cuts them") {
    ink_test::Session canvas(document);
    ink_canvas_set_eraser(canvas.get(), INK_ERASER_FREE, 1);
    Gesture(canvas.get(), Line({150, 280}, {150, 320}, 4), 0);
    std::vector<Stroke> pieces = Strokes(canvas.doc());  // no Shape remains
    // The closed outline cut once: from its start corner to the cut, and from the cut back.
    REQUIRE(pieces.size() == 2);
    Box all;
    for (const Stroke &piece : pieces) {
      CHECK(piece.brush == "marker");
      CHECK(piece.fill == rect.stroke);
      CHECK(piece.size == rect.stroke_width);
      for (Point p : PagePath(piece)) {
        all.Add(p);
        CHECK(ToRectEdge(p, 100, 300, 300, 400) < 1e-9);
        // Nothing of the top edge is left within the eraser's 7 units of x = 150.
        CHECK_FALSE((p.y == 300 && std::abs(p.x - 150) < 7 - 1e-9));
      }
    }
    CHECK(pieces[0].samples.front().x == 100);
    CHECK(std::abs(pieces[0].samples.back().x - 143) < 1e-9);
    CHECK(std::abs(pieces[1].samples.front().x - 157) < 1e-9);
    CHECK((all.left == 100 && all.top == 300 && all.right == 300 && all.bottom == 400));
  }
}

TEST_CASE("Both erasers leave hidden and locked layers unchanged") {
  const Document original = ProtectedLayerDocument();
  const Element hidden = *original.pages[0]->layers[1].elements[0];
  const Element locked = *original.pages[0]->layers[2].elements[0];

  SECTION("stroke eraser") {
    ink_test::Session canvas(original, 31);
    ink_canvas_set_eraser(canvas.get(), INK_ERASER_STROKE, 1);
    Gesture(canvas.get(), Line({200, 50}, {200, 350}, 20), 1000);

    CHECK(canvas.doc().pages[0]->layers[0].elements.empty());
    REQUIRE(canvas.doc().pages[0]->layers[1].elements.size() == 1);
    REQUIRE(canvas.doc().pages[0]->layers[2].elements.size() == 1);
    CHECK(*canvas.doc().pages[0]->layers[1].elements[0] == hidden);
    CHECK(*canvas.doc().pages[0]->layers[2].elements[0] == locked);
  }

  SECTION("free eraser") {
    ink_test::Session canvas(original, 32);
    ink_canvas_set_eraser(canvas.get(), INK_ERASER_FREE, 1);
    Gesture(canvas.get(), Line({200, 50}, {200, 350}, 20), 1000);

    CHECK(canvas.doc().pages[0]->layers[0].elements.size() == 2);
    REQUIRE(canvas.doc().pages[0]->layers[1].elements.size() == 1);
    REQUIRE(canvas.doc().pages[0]->layers[2].elements.size() == 1);
    CHECK(*canvas.doc().pages[0]->layers[1].elements[0] == hidden);
    CHECK(*canvas.doc().pages[0]->layers[2].elements[0] == locked);
  }
}
