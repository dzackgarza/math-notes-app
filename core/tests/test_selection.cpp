// Selection (issue #24): lasso and rectangle select, the handles, moves
// between pages, and the clipboard, against the selection cases recorded
// from Write (tests/fixtures/write: lasso-move-duplicate, rect-scale-rotate).
#include <catch2/catch_test_macros.hpp>

#include <algorithm>
#include <cmath>
#include <map>
#include <set>
#include <string>
#include <vector>

#include <pugixml.hpp>

#include "editor/canvas.h"
#include "format/notebook.h"
#include "format/page_svg.h"
#include "include/core/SkBitmap.h"
#include "include/core/SkColorSpace.h"
#include "include/core/SkSurface.h"
#include "layout/layout.h"
#include "render/renderer.h"
#include "support/notebook_dir.h"
#include "geometry/affine.h"
#include "selection/selection.h"
#include "support/session.h"
#include "support/write_fixture.h"

using namespace ink_engine;

namespace {

const std::string kWriteDir = INK_FIXTURE_DIR "/../../../tests/fixtures/write/";

const Elements &Layer0(const Document &document, size_t page = 0) {
  return document.pages[page]->layers[0].elements;
}

const Stroke &StrokeAt(const Document &document, size_t page, size_t index) {
  return std::get<Stroke>(Layer0(document, page)[index]->value);
}

// The document-order indices of the selected elements on layer 0.
std::set<int> SelectedIndices(InkCanvas *canvas) {
  std::set<int> indices;
  const Selection *selection = canvas->editor.CurrentSelection();
  if (!selection) return indices;
  for (const ElementRef &item : selection->items) indices.insert(int(item.index));
  return indices;
}

// Write's selection as document-order indices of page 0.
std::set<int> WriteSelectedIndices(const ink_test::WriteExpected &expected) {
  std::set<int> indices;
  for (size_t i = 0; i < expected.elements.size(); ++i) {
    if (expected.selected.contains(expected.elements[i].id)) indices.insert(int(i));
  }
  return indices;
}

void CheckTransform(const Transform &ours, const Transform &write) {
  CHECK(std::abs(ours.a - write.a) < 1e-4);
  CHECK(std::abs(ours.b - write.b) < 1e-4);
  CHECK(std::abs(ours.c - write.c) < 1e-4);
  CHECK(std::abs(ours.d - write.d) < 1e-4);
  CHECK(std::abs(ours.e - write.e) < 0.01);
  CHECK(std::abs(ours.f - write.f) < 0.01);
}

// A pen gesture in view coordinates, one ink_input call per sample.
void Gesture(InkCanvas *canvas, std::vector<Point> points, double t0) {
  for (size_t i = 0; i < points.size(); ++i) {
    InkPhase phase = i == 0 ? INK_PHASE_BEGIN : i + 1 == points.size() ? INK_PHASE_END : INK_PHASE_MOVE;
    InkPenSample s{.x = points[i].x, .y = points[i].y, .time = t0 + 10.0 * i, .pressure = 0.5f,
                   .tool = INK_TOOL_PEN, .phase = uint8_t(phase)};
    REQUIRE(ink_input(canvas, &s, 1) == INK_OK);
  }
}

std::vector<Point> Line(Point a, Point b, int n) {
  std::vector<Point> points;
  for (int i = 0; i <= n; ++i) points.push_back({a.x + (b.x - a.x) * i / n, a.y + (b.y - a.y) * i / n});
  return points;
}

// The files ink_document_dirty_files lists, by path.
std::map<std::string, std::string> DirtyFiles(InkDocument *document) {
  const InkFile *files = nullptr;
  size_t count = 0;
  REQUIRE(ink_document_dirty_files(document, &files, &count) == INK_OK);
  std::map<std::string, std::string> dirty;
  for (size_t i = 0; i < count; ++i) {
    dirty[files[i].path] = std::string(reinterpret_cast<const char *>(files[i].bytes), files[i].size);
  }
  return dirty;
}

struct SavedPath {
  std::string id, d, transform;
};

// The ink paths (id="s-…") of a page file.
std::vector<SavedPath> SavedPaths(const std::string &svg) {
  pugi::xml_document xml;
  REQUIRE(xml.load_string(svg.c_str()));
  std::vector<SavedPath> paths;
  for (pugi::xpath_node node : xml.select_nodes("//path[starts-with(@id, 's-')]")) {
    pugi::xml_node path = node.node();
    paths.push_back({path.attribute("id").value(), path.attribute("d").value(),
                     path.attribute("transform").value()});
  }
  return paths;
}

}  // namespace

TEST_CASE("A lasso selects the strokes Write selects; move and duplicate place them") {
  auto trace = ink_test::ReadWriteTrace(kWriteDir + "lasso-move-duplicate/trace.txt");
  auto expected = ink_test::ReadWriteExpected(kWriteDir + "lasso-move-duplicate/expected.json");
  ink_test::Session canvas;
  ink_test::ReplayWriteTrace(canvas.get(), trace);

  const Elements &elements = Layer0(canvas.doc());
  REQUIRE(elements.size() == expected.elements.size());
  CHECK(SelectedIndices(canvas.get()) == WriteSelectedIndices(expected));
  // The lasso took strokes 0-2, which the drag moved; 3 (half inside) and 4 stayed.
  for (size_t i = 0; i < 5; ++i) {
    INFO("stroke " << i);
    CheckTransform(std::get<Stroke>(elements[i]->value).transform, expected.elements[i].transform);
  }
  // Write duplicates one ruling right and down; #24 specifies 10 pt.
  for (size_t i = 0; i < 3; ++i) {
    const Stroke &original = std::get<Stroke>(elements[i]->value);
    const Stroke &copy = std::get<Stroke>(elements[5 + i]->value);
    CHECK(copy.id != original.id);
    CHECK(copy.outline == original.outline);
    CHECK(copy.transform == Compose(Translation(kDuplicateOffset, kDuplicateOffset), original.transform));
  }
}

TEST_CASE("Resizing, selecting all, scaling through a negative factor and rotating give Write's transforms") {
  auto trace = ink_test::ReadWriteTrace(kWriteDir + "rect-scale-rotate/trace.txt");
  auto expected = ink_test::ReadWriteExpected(kWriteDir + "rect-scale-rotate/expected.json");
  ink_test::Session canvas;
  std::vector<std::string> drawn = ink_test::ReplayWriteTrace(canvas.get(), trace);

  const Elements &elements = Layer0(canvas.doc());
  REQUIRE(elements.size() == expected.elements.size());
  CHECK(SelectedIndices(canvas.get()) == WriteSelectedIndices(expected));
  for (size_t i = 0; i < elements.size(); ++i) {
    INFO("stroke " << i);
    CheckTransform(std::get<Stroke>(elements[i]->value).transform, expected.elements[i].transform);
  }
  // Each handle drag is one history step; selecting adds none.
  CHECK(canvas.document->history.size() == 1 + drawn.size() + 3);

  // The page file keeps the transforms: read back, each stroke lands within
  // 0.01 pt of where the editor put it, anywhere on the page.
  Page saved = ReadPage(DirtyFiles(canvas.document).at("pages/0001.svg"), "pages/0001.svg", {});
  for (size_t i = 0; i < elements.size(); ++i) {
    INFO("stroke " << i);
    const Stroke &ours = std::get<Stroke>(elements[i]->value);
    const Stroke &read = std::get<Stroke>(saved.layers[0].elements[i]->value);
    for (Point corner : {Point{0, 0}, Point{595.28, 0}, Point{0, 841.89}, Point{595.28, 841.89}}) {
      Point a = Apply(ours.transform, corner), b = Apply(read.transform, corner);
      CHECK(std::hypot(a.x - b.x, a.y - b.y) < 0.01);
    }
  }
}

TEST_CASE("The lasso selects a stroke more than 90% inside it") {
  ink_test::Session canvas;
  ink_test::SetTool(canvas.get(), INK_BRUSH_MARKER, 0x1A1A1A, 2);
  Gesture(canvas.get(), Line({100, 100}, {300, 100}, 20), 0);  // 200 pt long
  ink_canvas_set_selector(canvas.get(), INK_SELECTOR_LASSO, 1);
  auto lasso = [&](double right) {
    Gesture(canvas.get(), {{80, 80}, {right, 80}, {right, 120}, {80, 120}, {80, 81}}, 1000);
    return canvas.canvas->editor.CurrentSelection() != nullptr;
  };
  CHECK(lasso(292));  // 95% of the stroke
  ink_canvas_clear_selection(canvas.get());
  CHECK_FALSE(lasso(250));  // 75%
}

TEST_CASE("A selection dragged from page 2 onto page 3 moves there; one undo restores both files") {
  ink_test::Session canvas;
  REQUIRE(ink_document_insert_page(canvas.document, 1) == INK_OK);
  REQUIRE(ink_document_insert_page(canvas.document, 2) == INK_OK);
  double x2, y2, w, h, x3, y3;
  REQUIRE(ink_document_page_rect(canvas.document, 1, &x2, &y2, &w, &h) == INK_OK);
  REQUIRE(ink_document_page_rect(canvas.document, 2, &x3, &y3, &w, &h) == INK_OK);
  ink_test::SetTool(canvas.get(), INK_BRUSH_PRESSURE_PEN, 0x1F4FD1, 2);
  Gesture(canvas.get(), Line({x2 + 100, y2 + 700}, {x2 + 260, y2 + 740}, 16), 0);
  std::map<std::string, std::string> before = DirtyFiles(canvas.document);
  REQUIRE(ink_document_mark_saved(canvas.document) == INK_OK);
  const std::string id = StrokeAt(canvas.doc(), 1, 0).id;
  Rect bounds = ElementBounds(*Layer0(canvas.doc(), 1)[0]);

  ink_canvas_set_selector(canvas.get(), INK_SELECTOR_RECT, 1);
  Gesture(canvas.get(), Line({x2 + 80, y2 + 680}, {x2 + 280, y2 + 760}, 4), 100);
  ink_canvas_set_selector(canvas.get(), INK_SELECTOR_RECT, 0);
  size_t steps = canvas.document->history.size();
  // From inside the selection to 300 pt further down: onto page 3.
  Point grab{x2 + 180, y2 + 720};
  Gesture(canvas.get(), Line(grab, {grab.x + 40, grab.y + 300}, 10), 200);

  CHECK(canvas.document->history.size() == steps + 1);
  CHECK(Layer0(canvas.doc(), 1).empty());
  REQUIRE(Layer0(canvas.doc(), 2).size() == 1);
  const Stroke &moved = StrokeAt(canvas.doc(), 2, 0);
  CHECK(moved.id == id);
  // The same absolute position: page 3 coordinates plus page 3's origin.
  Rect after = ElementBounds(*Layer0(canvas.doc(), 2)[0]);
  CHECK(std::abs(after.left + x3 - (bounds.left + x2 + 40)) < 1e-9);
  CHECK(std::abs(after.top + y3 - (bounds.top + y2 + 300)) < 1e-9);
  InkSelectionInfo info;
  REQUIRE(ink_canvas_selection(canvas.get(), &info) == INK_OK);
  CHECK((info.count == 1 && info.page == 2));

  std::map<std::string, std::string> moved_files = DirtyFiles(canvas.document);
  CHECK(moved_files.size() == 2);
  CHECK(SavedPaths(moved_files.at("pages/0002.svg")).empty());
  CHECK(SavedPaths(moved_files.at("pages/0003.svg")).at(0).id == id);
  REQUIRE(ink_document_mark_saved(canvas.document) == INK_OK);

  int32_t undone = 0, page = -1;
  REQUIRE(ink_undo(canvas.document, &undone, &page) == INK_OK);
  std::map<std::string, std::string> restored = DirtyFiles(canvas.document);
  CHECK(restored.size() == 2);
  CHECK(restored.at("pages/0002.svg") == before.at("pages/0002.svg"));
  CHECK(restored.at("pages/0003.svg") == before.at("pages/0003.svg"));
}

TEST_CASE("Copy in one notebook and paste in another: the same outline bytes and new ids") {
  ink_test::Session source(1);
  ink_test::SetTool(source.get(), INK_BRUSH_PRESSURE_PEN, 0xD6455D, 2.5f);
  Gesture(source.get(), Line({120, 200}, {320, 260}, 24), 0);
  Gesture(source.get(), Line({140, 300}, {200, 380}, 12), 500);
  REQUIRE(ink_canvas_select_all(source.get(), 0) == INK_OK);
  const uint8_t *svg = nullptr;
  size_t size = 0;
  REQUIRE(ink_canvas_copy_selection(source.get(), 0, &svg, &size) == INK_OK);
  std::string clipboard(reinterpret_cast<const char *>(svg), size);

  ink_test::Session target(2);
  REQUIRE(ink_canvas_set_surface_size(target.get(), 600, 850, 1) == INK_OK);
  REQUIRE(ink_canvas_paste(target.get(), reinterpret_cast<const uint8_t *>(clipboard.data()),
                           clipboard.size(), 300, 400) == INK_OK);
  InkSelectionInfo info;
  REQUIRE(ink_canvas_selection(target.get(), &info) == INK_OK);
  CHECK(info.count == 2);

  std::vector<SavedPath> copied = SavedPaths(DirtyFiles(source.document).at("pages/0001.svg"));
  std::vector<SavedPath> pasted = SavedPaths(DirtyFiles(target.document).at("pages/0001.svg"));
  REQUIRE(copied.size() == 2);
  REQUIRE(pasted.size() == 2);
  for (size_t i = 0; i < 2; ++i) {
    CHECK(pasted[i].d == copied[i].d);
    CHECK(pasted[i].transform == copied[i].transform);  // on the page: pasted in place
    CHECK(pasted[i].id != copied[i].id);
  }
  CHECK(ink_canvas_paste(target.get(), reinterpret_cast<const uint8_t *>("<svg"), 4, 0, 0) ==
        INK_ERROR_PARSE);
}

TEST_CASE("Cut keeps ids; pasting where an id exists gives the copy a new one") {
  ink_test::Session canvas;
  REQUIRE(ink_canvas_set_surface_size(canvas.get(), 600, 850, 1) == INK_OK);
  Gesture(canvas.get(), Line({120, 200}, {320, 260}, 24), 0);
  const std::string id = StrokeAt(canvas.doc(), 0, 0).id;
  REQUIRE(ink_canvas_select_all(canvas.get(), 0) == INK_OK);
  const uint8_t *svg = nullptr;
  size_t size = 0;
  REQUIRE(ink_canvas_copy_selection(canvas.get(), 1, &svg, &size) == INK_OK);
  std::string clipboard(reinterpret_cast<const char *>(svg), size);
  CHECK(Layer0(canvas.doc()).empty());

  auto paste = [&] {
    REQUIRE(ink_canvas_paste(canvas.get(), reinterpret_cast<const uint8_t *>(clipboard.data()),
                             clipboard.size(), 300, 400) == INK_OK);
  };
  paste();
  paste();
  REQUIRE(Layer0(canvas.doc()).size() == 2);
  CHECK(StrokeAt(canvas.doc(), 0, 0).id == id);
  CHECK(StrokeAt(canvas.doc(), 0, 1).id != id);
  CHECK(StrokeAt(canvas.doc(), 0, 1).outline == StrokeAt(canvas.doc(), 0, 0).outline);
}

TEST_CASE("Recoloring a selection changes only the selected strokes' color in one undo step") {
  ink_test::Session canvas;
  REQUIRE(ink_canvas_set_surface_size(canvas.get(), 600, 850, 1) == INK_OK);
  ink_test::SetTool(canvas.get(), INK_BRUSH_HIGHLIGHTER, 0xFFE066, 9.6, 0.35);
  Gesture(canvas.get(), Line({120, 200}, {320, 260}, 24), 0);
  ink_test::SetTool(canvas.get(), INK_BRUSH_PRESSURE_PEN, 0x1A1A1A, 1.2);
  Gesture(canvas.get(), Line({120, 400}, {320, 460}, 24), 1000);
  Gesture(canvas.get(), Line({120, 600}, {320, 660}, 24), 2000);
  const Document before = canvas.doc();
  // A rectangle over the first two strokes.
  ink_canvas_set_selector(canvas.get(), INK_SELECTOR_RECT, 1);
  Gesture(canvas.get(), Line({100, 180}, {340, 480}, 4), 3000);
  ink_canvas_set_selector(canvas.get(), INK_SELECTOR_RECT, 0);
  InkSelectionInfo selected{};
  REQUIRE(ink_canvas_selection(canvas.get(), &selected) == INK_OK);
  REQUIRE(selected.count == 2);

  REQUIRE(ink_canvas_recolor_selection(canvas.get(), 0x2F6FEB) == INK_OK);
  const Rgb blue{0x2F, 0x6F, 0xEB};
  for (size_t i : {0, 1}) {
    Stroke expected = StrokeAt(before, 0, i);
    expected.fill = blue;
    CHECK(StrokeAt(canvas.doc(), 0, i) == expected);
  }
  CHECK(StrokeAt(canvas.doc(), 0, 0).fill_opacity == StrokeAt(before, 0, 0).fill_opacity);
  CHECK(StrokeAt(canvas.doc(), 0, 2) == StrokeAt(before, 0, 2));
  InkSelectionInfo after{};
  REQUIRE(ink_canvas_selection(canvas.get(), &after) == INK_OK);
  CHECK(after.count == 2);

  int32_t moved = 0;
  int32_t page = 0;
  REQUIRE(ink_undo(canvas.document, &moved, &page) == INK_OK);
  CHECK(canvas.doc() == before);
}

TEST_CASE("Paste keeps the position only when it is in view; otherwise it centers on the view point") {
  ink_test::Session source(1);
  Gesture(source.get(), Line({120, 100}, {320, 160}, 20), 0);
  REQUIRE(ink_canvas_select_all(source.get(), 0) == INK_OK);
  const uint8_t *svg = nullptr;
  size_t size = 0;
  REQUIRE(ink_canvas_copy_selection(source.get(), 0, &svg, &size) == INK_OK);
  std::string clipboard(reinterpret_cast<const char *>(svg), size);
  Rect original = ElementBounds(*Layer0(source.doc())[0]);

  // The view shows content y 400 to 800; the copied stroke sits near y 130.
  ink_test::Session target(2);
  REQUIRE(ink_canvas_set_surface_size(target.get(), 600, 400, 1) == INK_OK);
  REQUIRE(ink_canvas_set_view(target.get(), 1, 0, 0, 1, 0, -400) == INK_OK);
  REQUIRE(ink_canvas_paste(target.get(), reinterpret_cast<const uint8_t *>(clipboard.data()),
                           clipboard.size(), 300, 200) == INK_OK);
  Rect pasted = ElementBounds(*Layer0(target.doc())[0]);
  CHECK(std::abs((pasted.left + pasted.right) / 2 - 300) < 1e-9);
  CHECK(std::abs((pasted.top + pasted.bottom) / 2 - 600) < 1e-9);
  CHECK(std::abs((pasted.right - pasted.left) - (original.right - original.left)) < 1e-3);

  // Scrolled back to the top, the same text pastes in place.
  REQUIRE(ink_canvas_set_view(target.get(), 1, 0, 0, 1, 0, 0) == INK_OK);
  REQUIRE(ink_canvas_paste(target.get(), reinterpret_cast<const uint8_t *>(clipboard.data()),
                           clipboard.size(), 300, 200) == INK_OK);
  Rect in_place = ElementBounds(*Layer0(target.doc())[1]);
  CHECK(std::abs(in_place.left - original.left) < 1e-3);
  CHECK(std::abs(in_place.top - original.top) < 1e-3);
}

TEST_CASE("An image pasted into another notebook gets its own asset file and renders from it") {
  const std::string dir = std::string(INK_DOCUMENTS_DIR) + "/full";
  ink_test::Session source(LoadNotebook(ink_test::ReadNotebookDir(dir)));
  const std::string diagram = ink_test::ReadFile(dir + "/assets/diagram.png");
  for (const auto &[path, bytes] : ink_test::ReadAssets(dir)) {
    REQUIRE(ink_document_load_asset(source.document, path.c_str(),
                                    reinterpret_cast<const uint8_t *>(bytes.data()), bytes.size()) == INK_OK);
  }
  // The image s-pastedimage fills (60, 400)-(180, 490) of page 1.
  ink_canvas_set_selector(source.get(), INK_SELECTOR_RECT, 1);
  Gesture(source.get(), Line({50, 390}, {190, 500}, 4), 0);
  InkSelectionInfo info;
  REQUIRE(ink_canvas_selection(source.get(), &info) == INK_OK);
  REQUIRE(info.count == 1);
  const uint8_t *svg = nullptr;
  size_t size = 0;
  REQUIRE(ink_canvas_copy_selection(source.get(), 0, &svg, &size) == INK_OK);
  std::string clipboard(reinterpret_cast<const char *>(svg), size);

  ink_test::Session target(2);
  REQUIRE(ink_canvas_set_surface_size(target.get(), 600, 850, 1) == INK_OK);
  auto paste = [&] {
    REQUIRE(ink_canvas_paste(target.get(), reinterpret_cast<const uint8_t *>(clipboard.data()),
                             clipboard.size(), 300, 400) == INK_OK);
  };
  paste();
  std::map<std::string, std::string> files = DirtyFiles(target.document);
  std::vector<std::string> assets;
  for (const auto &[path, bytes] : files) {
    if (path.starts_with("assets/")) assets.push_back(path);
  }
  REQUIRE(assets.size() == 1);
  CHECK(files.at(assets[0]) == diagram);
  const Image &image = std::get<Image>(Layer0(target.doc())[0]->value);
  CHECK(image.href == "../" + assets[0]);
  REQUIRE(ink_document_mark_saved(target.document) == INK_OK);

  // A second paste reuses the file.
  paste();
  for (const auto &[path, bytes] : DirtyFiles(target.document)) CHECK_FALSE(path.starts_with("assets/"));

  // Reopened from its own files, the target draws the image from its asset:
  // without that one file, the same page shows paper there.
  NotebookFiles saved(files.begin(), files.end());
  ink_test::Session reopened(LoadNotebook(saved), 3), without_asset(LoadNotebook(saved), 4);
  REQUIRE(ink_document_load_asset(reopened.document, assets[0].c_str(),
                                  reinterpret_cast<const uint8_t *>(files.at(assets[0]).data()),
                                  files.at(assets[0]).size()) == INK_OK);
  auto image_pixels = [](InkDocument *document) {
    Renderer renderer(nullptr, document->assets);
    const Document &doc = document->history.current();
    View view{{1, 0, 0, 1, 0, 0}, 1, 600, 850};
    REQUIRE(renderer.Update(doc, view, false));
    sk_sp<SkSurface> screen =
        SkSurfaces::Raster(SkImageInfo::MakeN32Premul(600, 850, SkColorSpace::MakeSRGB()));
    renderer.Draw(screen->getCanvas(), nullptr, nullptr);
    SkBitmap bitmap;
    bitmap.allocPixels(SkImageInfo::Make(600, 850, kRGBA_8888_SkColorType, kUnpremul_SkAlphaType));
    REQUIRE(screen->readPixels(bitmap, 0, 0));
    int count = 0;  // pixels of the image's box that are not paper
    for (int y = 400; y < 490; ++y) {
      for (int x = 60; x < 180; ++x) count += bitmap.getColor(x, y) != bitmap.getColor(590, 840);
    }
    return count;
  };
  CHECK(image_pixels(reopened.document) > 1000);
  CHECK(image_pixels(without_asset.document) == 0);
}
