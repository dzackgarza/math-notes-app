// The C ABI's documents, statuses and errors (issue #4).
#include <catch2/catch_test_macros.hpp>

#include <array>
#include <cstdlib>
#include <map>
#include <set>
#include <string>

#include "editor/canvas.h"
#include "include/codec/SkCodec.h"
#include "include/codec/SkPngDecoder.h"
#include "include/core/SkBitmap.h"
#include "include/core/SkColorSpace.h"
#include "include/core/SkData.h"
#include "format/notebook.h"
#include "ink.h"
#include "support/notebook_dir.h"
#include "support/session.h"

using namespace ink_engine;

namespace {

const std::string kDocuments = INK_DOCUMENTS_DIR;

const uint8_t *Data(const std::string &bytes) {
  return reinterpret_cast<const uint8_t *>(bytes.data());
}

std::map<std::string, std::string> DirtyFiles(InkDocument *document) {
  const InkFile *files = nullptr;
  size_t count = 0;
  REQUIRE(ink_document_dirty_files(document, &files, &count) == INK_OK);
  std::map<std::string, std::string> out;
  for (size_t i = 0; i < count; ++i) {
    out[files[i].path] = std::string(reinterpret_cast<const char *>(files[i].bytes), files[i].size);
  }
  return out;
}

void DrawLine(InkCanvas *canvas, double y) {
  InkPenSample samples[] = {
      {.x = 100, .y = y, .time = 0, .tool = INK_TOOL_PEN, .phase = INK_PHASE_BEGIN},
      {.x = 150, .y = y, .time = 20, .id = 1, .tool = INK_TOOL_PEN, .phase = INK_PHASE_MOVE},
      {.x = 200, .y = y, .time = 40, .id = 2, .tool = INK_TOOL_PEN, .phase = INK_PHASE_END}};
  REQUIRE(ink_input(canvas, samples, 3) == INK_OK);
}

}  // namespace

TEST_CASE("A page that does not parse gives a parse status and its message") {
  ink_test::Session session;
  std::string bad = "<svg><g id=\"l-aaaaaa\">\n<<<<<<< HEAD\n</g></svg>";
  CHECK(ink_document_load_page(session.document, "pages/0001.svg", Data(bad), bad.size()) ==
        INK_ERROR_PARSE);
  CHECK(std::string(ink_last_error()) == "pages/0001.svg: Could not determine tag type at offset 24");
  // The page stays in the document as an error page, which is never written.
  const Page &page = *session.doc().pages[0];
  CHECK(page.error.has_value());
  CHECK_FALSE(DirtyFiles(session.document).contains("pages/0001.svg"));
}

TEST_CASE("notebook.json that does not parse gives a parse status and its message") {
  ink_test::Session session;
  std::string bad = "{\"title\": ";
  CHECK(ink_document_load_notebook(session.document, Data(bad), bad.size()) == INK_ERROR_PARSE);
  CHECK(std::string(ink_last_error()).starts_with("[json.exception.parse_error.101]"));
}

TEST_CASE("A null handle or pointer gives an argument status") {
  int32_t drew = 0;
  CHECK(ink_render(nullptr, &drew) == INK_ERROR_ARGUMENT);
  CHECK(std::string(ink_last_error()) == "canvas is null");
  CHECK(ink_document_create(1, nullptr) == INK_ERROR_ARGUMENT);
  ink_test::Session session;
  CHECK(ink_canvas_set_tool(session.get(), nullptr) == INK_ERROR_ARGUMENT);
  InkToolSettings unknown{7, 0, 1, 1};
  CHECK(ink_canvas_set_tool(session.get(), &unknown) == INK_ERROR_ARGUMENT);
  CHECK(ink_canvas_set_view(session.get(), 0, 0, 0, 0, 0, 0) == INK_ERROR_ARGUMENT);
}

TEST_CASE("Drawing mode completes one editable figure and removes its files when deleted") {
  ink_test::Session session;
  REQUIRE(ink_document_mark_saved(session.document) == INK_OK);
  REQUIRE(ink_canvas_figure_begin(session.get(), 0, 0) == INK_OK);
  DrawLine(session.get(), 100);
  DrawLine(session.get(), 120);
  const uint8_t *scene = nullptr;
  size_t scene_size = 0;
  REQUIRE(ink_canvas_figure_scene(session.get(), &scene, &scene_size) == INK_OK);
  std::string scene_bytes(reinterpret_cast<const char *>(scene), scene_size);
  CHECK(scene_bytes.find("\"rawStroke\"") != std::string::npos);
  CHECK(scene_bytes.find("\"force\"") != std::string::npos);
  const std::string tikz = "\\begin{tikzpicture}\\draw (0,0)--(1,1);\\end{tikzpicture}\n";
  const uint8_t *id = nullptr;
  size_t id_size = 0;
  REQUIRE(ink_canvas_figure_complete(session.get(), Data(scene_bytes), scene_bytes.size(),
                                     Data(tikz), tikz.size(), &id, &id_size) == INK_OK);
  const std::string figure_id(reinterpret_cast<const char *>(id), id_size);
  REQUIRE(figure_id.starts_with("f-"));
  const auto &elements = session.doc().pages[0]->layers[0].elements;
  REQUIRE(elements.size() == 1);
  const Figure &figure = std::get<Figure>(elements[0]->value);
  CHECK(figure.id == figure_id);
  CHECK(figure.children.size() == 2);
  auto changed = DirtyFiles(session.document);
  CHECK(changed.at("assets/" + figure_id + ".scene.json") == scene_bytes);
  CHECK(changed.at("assets/" + figure_id + ".tikz") == tikz);
  CHECK(changed.at("pages/0001.svg").find("class=\"mn-figure\"") != std::string::npos);

  REQUIRE(ink_document_mark_saved(session.document) == INK_OK);
  REQUIRE(ink_canvas_select_all(session.get(), 0) == INK_OK);
  REQUIRE(ink_canvas_delete_selection(session.get()) == INK_OK);
  const InkFile *files = nullptr;
  size_t count = 0;
  REQUIRE(ink_document_dirty_files(session.document, &files, &count) == INK_OK);
  std::set<std::string> removed;
  for (size_t i = 0; i < count; ++i) {
    if (files[i].kind == INK_FILE_DELETE) removed.insert(files[i].path);
  }
  CHECK(removed.contains("assets/" + figure_id + ".scene.json"));
  CHECK(removed.contains("assets/" + figure_id + ".tikz"));
}

TEST_CASE("A duplicated figure has its own scene and TikZ files") {
  ink_test::Session session;
  REQUIRE(ink_canvas_figure_begin(session.get(), 0, 0) == INK_OK);
  DrawLine(session.get(), 100);
  const uint8_t *scene = nullptr;
  size_t size = 0;
  REQUIRE(ink_canvas_figure_scene(session.get(), &scene, &size) == INK_OK);
  const std::string scene_bytes(reinterpret_cast<const char *>(scene), size);
  const std::string tikz = "\\begin{tikzpicture}\\end{tikzpicture}\n";
  const uint8_t *id = nullptr;
  size_t id_size = 0;
  REQUIRE(ink_canvas_figure_complete(session.get(), Data(scene_bytes), scene_bytes.size(),
                                     Data(tikz), tikz.size(), &id, &id_size) == INK_OK);
  REQUIRE(ink_canvas_select_all(session.get(), 0) == INK_OK);
  REQUIRE(ink_canvas_duplicate_selection(session.get()) == INK_OK);
  const auto &elements = session.doc().pages[0]->layers[0].elements;
  REQUIRE(elements.size() == 2);
  const Figure &first = std::get<Figure>(elements[0]->value);
  const Figure &second = std::get<Figure>(elements[1]->value);
  CHECK(first.id != second.id);
  CHECK(first.scene_href != second.scene_href);
  CHECK(first.tikz_href != second.tikz_href);
  const auto dirty = DirtyFiles(session.document);
  CHECK(dirty.at("assets/" + second.id + ".scene.json") == scene_bytes);
  CHECK(dirty.at("assets/" + second.id + ".tikz") == tikz);
  const uint8_t *selected = nullptr;
  size_t selected_size = 0;
  REQUIRE(ink_canvas_selected_figure(session.get(), &selected, &selected_size) == INK_OK);
  CHECK(std::string(reinterpret_cast<const char *>(selected), selected_size) == second.id);
  const uint8_t *asset = nullptr;
  size_t asset_size = 0;
  REQUIRE(ink_document_asset(session.document, ("assets/" + second.id + ".tikz").c_str(),
                             &asset, &asset_size) == INK_OK);
  CHECK(std::string(reinterpret_cast<const char *>(asset), asset_size) == tikz);
}

TEST_CASE("An empty drawing session leaves the page and assets unchanged") {
  ink_test::Session session;
  REQUIRE(ink_document_mark_saved(session.document) == INK_OK);
  REQUIRE(ink_canvas_figure_begin(session.get(), 0, 0) == INK_OK);
  const uint8_t *id = nullptr;
  size_t id_size = 1;
  REQUIRE(ink_canvas_figure_complete(session.get(), nullptr, 0, nullptr, 0,
                                     &id, &id_size) == INK_OK);
  CHECK(id_size == 0);
  CHECK(DirtyFiles(session.document).empty());
}

TEST_CASE("A notebook loaded file by file equals the notebook loaded at once") {
  NotebookFiles files = ink_test::ReadNotebookDir(kDocuments + "/full");
  ink_test::Session session;
  const std::string &json = files.at("notebook.json");
  REQUIRE(ink_document_load_notebook(session.document, Data(json), json.size()) == INK_OK);
  // Pages in reverse name order: placement follows notebook.json and names.
  for (auto it = files.rbegin(); it != files.rend(); ++it) {
    if (it->first == "notebook.json") continue;
    InkStatus status =
        ink_document_load_page(session.document, it->first.c_str(), Data(it->second), it->second.size());
    CHECK(status == (it->first == "pages/0006.svg" ? INK_ERROR_PARSE : INK_OK));
  }
  CHECK(AllFiles(session.doc()) == AllFiles(LoadNotebook(files)));
  CHECK(DirtyFiles(session.document).empty());  // loaded files are saved
}

TEST_CASE("Dirty files are the changed pages until the host marks them saved") {
  ink_test::Session session;
  auto first = DirtyFiles(session.document);  // a new notebook was never saved
  CHECK(first.contains("notebook.json"));
  CHECK(first.contains("pages/0001.svg"));
  REQUIRE(ink_document_mark_saved(session.document) == INK_OK);
  CHECK(DirtyFiles(session.document).empty());

  DrawLine(session.get(), 100);
  auto changed = DirtyFiles(session.document);
  CHECK(changed.size() == 1);
  CHECK(changed.at("pages/0001.svg") == AllFiles(session.doc()).at("pages/0001.svg"));
  ink_document_mark_saved(session.document);
  CHECK(DirtyFiles(session.document).empty());
}

TEST_CASE("Undo and redo move through the document values") {
  ink_test::Session session;
  DrawLine(session.get(), 100);
  DrawLine(session.get(), 200);
  auto strokes = [&] { return session.doc().pages[0]->layers[0].elements.size(); };
  REQUIRE(strokes() == 2);
  int32_t moved = 0, page = 0;
  REQUIRE(ink_undo(session.document, &moved, &page) == INK_OK);
  CHECK((moved == 1 && strokes() == 1));
  ink_undo(session.document, &moved, &page);
  ink_undo(session.document, &moved, &page);
  CHECK((moved == 0 && strokes() == 0));
  ink_redo(session.document, &moved, &page);
  CHECK((moved == 1 && strokes() == 1));
  // A new stroke after an undo drops the redo branch.
  DrawLine(session.get(), 300);
  ink_redo(session.document, &moved, &page);
  CHECK((moved == 0 && strokes() == 2));
}

TEST_CASE("A page thumbnail is a PNG of the page's ink and image and paper at the given width") {
  // As the library loads a notebook for its thumbnail: notebook.json, page 1
  // and the assets, with no canvas.
  NotebookFiles files = ink_test::ReadNotebookDir(kDocuments + "/full");
  InkDocument *document = nullptr;
  REQUIRE(ink_document_create(1, &document) == INK_OK);
  const std::string &json = files.at("notebook.json");
  const std::string &page = files.at("pages/0001.svg");
  REQUIRE(ink_document_load_notebook(document, Data(json), json.size()) == INK_OK);
  REQUIRE(ink_document_load_page(document, "pages/0001.svg", Data(page), page.size()) == INK_OK);
  for (const auto &[path, bytes] : ink_test::ReadAssets(kDocuments + "/full")) {
    REQUIRE(ink_document_load_asset(document, path.c_str(), Data(bytes), bytes.size()) == INK_OK);
  }
  const uint8_t *png = nullptr;
  size_t size = 0;
  REQUIRE(ink_document_page_png(document, 0, 240, &png, &size) == INK_OK);

  auto codec = SkPngDecoder::Decode(SkData::MakeWithCopy(png, size), nullptr);
  REQUIRE(codec);
  CHECK(codec->getInfo().width() == 240);
  CHECK(codec->getInfo().height() == 339);  // 841.89 pt × 240 / 595.28
  SkBitmap bitmap;
  bitmap.allocPixels(SkImageInfo::Make(240, 339, kRGBA_8888_SkColorType, kUnpremul_SkAlphaType,
                                       SkColorSpace::MakeSRGB()));
  REQUIRE(codec->getPixels(bitmap.pixmap()) == SkCodec::kSuccess);
  const double scale = 240 / 595.28;
  auto rgb = [&](double x_pt, double y_pt) {
    SkColor c = bitmap.getColor(int(x_pt * scale), int(y_pt * scale));
    return std::array<int, 3>{int(SkColorGetR(c)), int(SkColorGetG(c)), int(SkColorGetB(c))};
  };
  auto near = [](std::array<int, 3> a, std::array<int, 3> b) {
    for (int i = 0; i < 3; ++i) {
      if (std::abs(a[i] - b[i]) > 3) return false;
    }
    return true;
  };
  // The highlighter stroke: #003399 at fill-opacity 0.4 over white paper,
  // translated by (12.5, -4) from its outline at (200..250, 100..108).
  CHECK(near(rgb(237.5, 100), {153, 173, 214}));
  // diagram.png, one red pixel at alpha 127, scaled over (60..180, 400..490).
  CHECK(near(rgb(120, 445), {255, 128, 128}));
  CHECK(near(rgb(500, 700), {255, 255, 255}));  // the paper

  ink_document_free(document);
}
