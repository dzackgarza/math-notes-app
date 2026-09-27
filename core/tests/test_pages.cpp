// Page operations, page sizes and templates through the C ABI (issue #21).
#include <catch2/catch_test_macros.hpp>

#include <map>
#include <string>

#include "document/templates.h"
#include "format/notebook.h"
#include "format/page_svg.h"
#include "ink.h"
#include "support/session.h"

using namespace ink_engine;

namespace {

struct Change {
  std::string bytes;
  uint32_t kind;
};

std::map<std::string, Change> DirtyFiles(InkDocument *document) {
  const InkFile *files = nullptr;
  size_t count = 0;
  REQUIRE(ink_document_dirty_files(document, &files, &count) == INK_OK);
  std::map<std::string, Change> out;
  for (size_t i = 0; i < count; ++i) {
    std::string bytes = files[i].bytes ? std::string(reinterpret_cast<const char *>(files[i].bytes), files[i].size) : "";
    out[files[i].path] = {bytes, files[i].kind};
  }
  return out;
}

std::vector<std::string> ListedFiles(const Document &document) {
  std::vector<std::string> files;
  for (size_t i = 0; i < ListedPageCount(document); ++i) files.push_back(document.pages[i]->file);
  return files;
}

// A saved notebook with pages 0001.svg to 0003.svg.
void ThreePages(ink_test::Session &session) {
  REQUIRE(ink_document_insert_page(session.document, 1) == INK_OK);
  REQUIRE(ink_document_insert_page(session.document, 2) == INK_OK);
  REQUIRE(ink_document_mark_saved(session.document) == INK_OK);
}

}  // namespace

TEST_CASE("A page inserted between pages 1 and 2 gets a new file and changes no other page") {
  ink_test::Session session;
  ThreePages(session);
  std::map<std::string, std::string> before = AllFiles(session.doc());
  REQUIRE(ink_document_insert_page(session.document, 1) == INK_OK);

  CHECK(ListedFiles(session.doc()) ==
        std::vector<std::string>{"pages/0001.svg", "pages/0004.svg", "pages/0002.svg", "pages/0003.svg"});
  auto dirty = DirtyFiles(session.document);
  CHECK(dirty.size() == 2);
  CHECK(dirty.contains("notebook.json"));
  CHECK(dirty.contains("pages/0004.svg"));
  std::map<std::string, std::string> after = AllFiles(session.doc());
  for (const char *file : {"pages/0001.svg", "pages/0002.svg", "pages/0003.svg"}) {
    CHECK(after.at(file) == before.at(file));
  }
}

TEST_CASE("A deleted page's file is listed for deletion; a moved page changes only notebook.json") {
  ink_test::Session session;
  ThreePages(session);
  REQUIRE(ink_document_move_page(session.document, 0, 2) == INK_OK);
  CHECK(ListedFiles(session.doc()) ==
        std::vector<std::string>{"pages/0002.svg", "pages/0003.svg", "pages/0001.svg"});
  auto moved = DirtyFiles(session.document);
  CHECK(moved.size() == 1);
  CHECK(moved.contains("notebook.json"));
  ink_document_mark_saved(session.document);

  REQUIRE(ink_document_delete_page(session.document, 1) == INK_OK);
  auto deleted = DirtyFiles(session.document);
  CHECK(deleted.at("pages/0003.svg").kind == INK_FILE_DELETE);
  CHECK(deleted.at("notebook.json").kind == INK_FILE_WRITE);
  CHECK(deleted.size() == 2);

  // Undo restores the saved value: nothing to write or delete.
  int32_t undone = 0;
  int32_t page = 0;
  ink_undo(session.document, &undone, &page);
  CHECK(DirtyFiles(session.document).empty());
  CHECK(ink_document_delete_page(session.document, 3) == INK_ERROR_ARGUMENT);
}

TEST_CASE("New pages take the notebook's page size") {
  ink_test::Session session;
  ink_document_insert_page(session.document, 1);
  CHECK(session.doc().pages[1]->width == 595.28);
  CHECK(session.doc().pages[1]->height == 841.89);
  REQUIRE(ink_document_set_page_size(session.document, INK_PAGE_LETTER, 0, 0) == INK_OK);
  ink_document_insert_page(session.document, 2);
  CHECK(session.doc().pages[2]->width == 612);
  CHECK(session.doc().pages[2]->height == 792);
  CHECK(DirtyFiles(session.document).at("notebook.json").bytes.find("\"pageSize\": \"Letter\"") !=
        std::string::npos);
  REQUIRE(ink_document_set_page_size(session.document, INK_PAGE_CUSTOM, 500, 700.5) == INK_OK);
  ink_document_insert_page(session.document, 0);
  CHECK(session.doc().pages[0]->width == 500);
  CHECK(session.doc().pages[0]->height == 700.5);
}

TEST_CASE("A new page copies the template's background, regenerated for another page size") {
  InkDocument *lined = nullptr;
  REQUIRE(ink_builtin_template_create("lined-medium", 3, &lined) == INK_OK);
  const std::string page1 = AllFiles(lined->history.current()).at("pages/0001.svg");
  ink_document_free(lined);

  ink_test::Session session;
  const auto *svg = reinterpret_cast<const uint8_t *>(page1.data());
  REQUIRE(ink_document_set_template(session.document, "lined-medium", svg, page1.size()) == INK_OK);
  CHECK(session.doc().notebook.template_name == "lined-medium");
  ink_document_insert_page(session.document, 1);
  const Background &a4 = session.doc().pages[1]->background;
  CHECK(a4 == session.document->template_page->background);

  ink_document_set_page_size(session.document, INK_PAGE_LETTER, 0, 0);
  ink_document_insert_page(session.document, 2);
  const Page &letter = *session.doc().pages[2];
  CHECK(letter.background.ruling == Ruling::kLined);
  CHECK(letter.background.y_ruling == 19.2);
  // Rows reach the bottom of the taller Letter page (792 pt; 41 rows of 19.2 pt).
  CHECK(letter.background.lines[0].d.size() == 41);
  CHECK(letter.background.lines[0].d.back()[1].x == 612);

  std::string bad = "<svg><<<";
  CHECK(ink_document_set_template(session.document, "broken", reinterpret_cast<const uint8_t *>(bad.data()),
                                  bad.size()) == INK_ERROR_PARSE);
}

TEST_CASE("The page under a view point, and the pages' extent") {
  ink_test::Session session;
  ink_document_insert_page(session.document, 1);
  InkCanvas *canvas = session.get();
  REQUIRE(ink_canvas_set_view(canvas, 0.5, 0, 0, 0.5, 0, 0) == INK_OK);
  int32_t page = 0;
  ink_canvas_page_at(canvas, 100, 100, &page);
  CHECK(page == 0);
  ink_canvas_page_at(canvas, 100, (841.89 + 3) * 0.5, &page);
  CHECK(page == -1);  // desk gap
  ink_canvas_page_at(canvas, 100, (841.89 + 100) * 0.5, &page);
  CHECK(page == 1);
  ink_canvas_page_at(canvas, 100, (2 * 841.89 + 100) * 0.5, &page);
  CHECK(page == -1);  // below the last page
  ink_canvas_page_at(canvas, 400, 100, &page);
  CHECK(page == -1);  // beside the page
  double width = 0, height = 0;
  ink_document_content_size(session.document, &width, &height);
  CHECK(height == 2 * 841.89 + 6);
}

TEST_CASE("Built-in templates are the Write presets") {
  size_t count = 0;
  REQUIRE(ink_builtin_template_count(&count) == INK_OK);
  std::vector<std::string> names;
  for (size_t i = 0; i < count; ++i) {
    const char *name = nullptr;
    REQUIRE(ink_builtin_template_name(i, &name) == INK_OK);
    names.push_back(name);
  }
  CHECK(names == std::vector<std::string>{"blank", "lined-wide", "lined-medium", "lined-narrow",
                                          "grid-coarse", "grid-medium", "grid-fine", "dotted"});
  InkDocument *unknown = nullptr;
  CHECK(ink_builtin_template_create("plaid", 1, &unknown) == INK_ERROR_ARGUMENT);
}

TEST_CASE("A notebook created from a template has page 1 on its background") {
  InkDocument *dotted = nullptr;
  REQUIRE(ink_builtin_template_create("dotted", 3, &dotted) == INK_OK);
  const std::string page1 = AllFiles(dotted->history.current()).at("pages/0001.svg");
  const Background expected = ReadPage(page1, "pages/0001.svg", {}).background;
  ink_document_free(dotted);

  InkDocument *document = nullptr;
  const auto *svg = reinterpret_cast<const uint8_t *>(page1.data());
  REQUIRE(ink_document_create_from_template(5, "dotted", svg, page1.size(), INK_PAGE_A4, 0, 0, &document) == INK_OK);
  const Document &doc = document->history.current();
  CHECK(doc.notebook.template_name == "dotted");
  REQUIRE(doc.pages.size() == 1);
  CHECK(doc.pages[0]->background == expected);
  int32_t moved = 1, page = 0;
  ink_undo(document, &moved, &page);
  CHECK(moved == 0);
  ink_document_free(document);
}
