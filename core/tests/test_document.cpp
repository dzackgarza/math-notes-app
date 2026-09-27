// Notebook and page file read and write (docs/FORMAT.md).
#include <catch2/catch_test_macros.hpp>

#include <cstdio>
#include <string>

#include "document/ids.h"
#include "format/notebook.h"
#include "format/numbers.h"
#include "format/page_svg.h"
#include "ink/strokes/stroke.h"
#include "support/notebook_dir.h"
#include "support/trace.h"

using namespace ink_engine;

namespace {

const std::string kDocuments = INK_DOCUMENTS_DIR;
const std::string kExpected = INK_FIXTURE_DIR "/documents/";
const char *kNotebooks[] = {"full", "custom-size"};

NotebookFiles Rewrite(const NotebookFiles &files) { return AllFiles(LoadNotebook(files)); }

}  // namespace

TEST_CASE("Numbers are fixed precision without trailing zeros or negative zero") {
  CHECK(FormatNumber(-0.0001, 2) == "0");
  CHECK(FormatNumber(1.50, 2) == "1.5");
  CHECK(FormatNumber(595.28, 2) == "595.28");
  CHECK(FormatNumber(-12.345, 2) == "-12.35");  // round half to even is not used: 12.345 is 12.3449…
  CHECK(FormatNumber(0.1234, 3) == "0.123");
  CHECK(FormatNumber(16.6, 0) == "17");
}

TEST_CASE("Hand-made notebooks write the same bytes on a second round trip") {
  for (const char *name : kNotebooks) {
    INFO(name);
    NotebookFiles first = Rewrite(ink_test::ReadNotebookDir(kDocuments + "/" + name));
    NotebookFiles second = Rewrite(first);
    REQUIRE(first == second);
    // The same bytes as the expected output, which pins them across hosts.
    NotebookFiles expected = ink_test::ReadNotebookDir(kExpected + name);
    REQUIRE(first == expected);
  }
}

TEST_CASE("A notebook loads listed pages, then unlisted pages, and error pages") {
  Document doc = LoadNotebook(ink_test::ReadNotebookDir(kDocuments + "/full"));
  REQUIRE(doc.pages.size() == 6);
  CHECK(doc.pages[3]->file == "pages/0004.svg");
  CHECK(doc.pages[5]->file == "pages/0005.svg");
  CHECK(doc.pages[5]->unlisted);

  const Page &conflict = *doc.pages[4];
  CHECK(conflict.file == "pages/0006.svg");
  REQUIRE(conflict.error.has_value());
  // pugixml status_unrecognized_tag, at the first "<<<<<<<" line.
  CHECK(*conflict.error == "Could not determine tag type at offset 237");

  NotebookFiles written = AllFiles(doc);
  CHECK_FALSE(written.contains("pages/0006.svg"));
  CHECK(written.contains("pages/0005.svg"));
  // The unlisted page stays unlisted: notebook.json does not gain it.
  CHECK(written["notebook.json"].find("0005.svg") == std::string::npos);
  CHECK(NextPageFile(doc) == "pages/0007.svg");
}

TEST_CASE("Changing one stroke on page 5 of 10 dirties only pages/0005.svg") {
  NotebookFiles source = ink_test::ReadNotebookDir(kDocuments + "/full");
  NotebookFiles files;
  std::string json = R"({"layers":[{"id":"l-inkaaa"},{"id":"l-notesb"}],"pages":[)";
  for (int i = 1; i <= 10; ++i) {
    char file[32];
    std::snprintf(file, sizeof file, "pages/%04d.svg", i);
    files[file] = source["pages/0001.svg"];
    json += std::string(i > 1 ? "," : "") + R"({"id":"p-)" + std::to_string(i) + R"(","file":")" + file + "\"}";
  }
  files["notebook.json"] = json + "]}";
  Document saved = LoadNotebook(files);

  Page page5 = *saved.pages[4];
  LayerContent &ink = page5.layers[0];
  Stroke stroke = std::get<Stroke>(ink.elements[0]->value);
  stroke.transform.e += 10;
  ink.elements = ink.elements.set(0, immer::box<Element>(Element{stroke}));
  Document current = saved;
  current.pages = current.pages.set(4, immer::box<Page>(page5));

  NotebookFiles changed = ChangedFiles(current, &saved);
  REQUIRE(changed.size() == 1);
  CHECK(changed.begin()->first == "pages/0005.svg");
}

TEST_CASE("Ids come from a seedable generator") {
  IdGenerator a(42), b(42);
  std::string page = a.PageId(), stroke = a.StrokeId();
  CHECK(page == b.PageId());
  CHECK(stroke == b.StrokeId());
  CHECK(page.size() == 8);
  CHECK(stroke.size() == 14);
  CHECK(page.starts_with("p-"));
  CHECK(stroke.find_first_not_of("abcdefghijklmnopqrstuvwxyz234567", 2) == std::string::npos);
}

TEST_CASE("A page with 400 recorded strokes") {
  auto inputs = ink_test::RealInputs(ink_test::ReadTrace(INK_FIXTURE_DIR "/ink/spring_shape.trace"));
  ink::Stroke recorded(ink_test::StockTestBrushes()[1].brush, inputs);

  Stroke stroke{.fill = {26, 26, 26}, .brush = "pressure-pen", .size = 5,
                .time = "2026-09-25T17:43:21.123Z",
                .channels = kChannelX | kChannelY | kChannelT | kChannelF | kChannelOE | kChannelOA};
  for (const auto &v : ink_test::Outline(recorded)) {
    if (stroke.outline.size() <= v.group + v.outline) stroke.outline.emplace_back();
    stroke.outline[v.group + v.outline].push_back({v.position.x, v.position.y});
  }
  for (ink::StrokeInput in : inputs) {
    stroke.samples.push_back({.x = in.position.x, .y = in.position.y,
                              .t = in.elapsed_time.ToMillis(), .force = in.pressure,
                              .altitude = in.tilt.ValueInRadians(),
                              .azimuth = in.orientation.ValueInRadians()});
  }

  IdGenerator ids(7);
  Page page{.id = ids.PageId(), .file = "pages/0001.svg", .width = 595.28, .height = 841.89};
  LayerContent layer{.layer_id = ids.LayerId()};
  for (int i = 0; i < 400; ++i) {
    stroke.id = ids.StrokeId();
    stroke.transform = {.e = double(i % 20) * 25, .f = double(i / 20) * 40};
    layer.elements = std::move(layer.elements).push_back(immer::box<Element>(Element{stroke}));
  }
  page.layers.push_back(layer);
  std::string bytes = WritePage(page);
  std::printf("400 recorded strokes (%zu samples, %zu outline vertices each): %zu bytes\n",
              stroke.samples.size(), ink_test::Outline(recorded).size(), bytes.size());
  CHECK(ReadPage(bytes, page.file, {layer.layer_id}).layers[0].elements.size() == 400);
}

TEST_CASE("A TikZ figure stays visible in standalone SVG and retains its editable references") {
  Stroke ink{.id = "s-3kd92lq0mzpa", .fill = {26, 26, 26}, .brush = "pressure-pen",
             .size = 2, .time = "2026-09-25T17:43:21.123Z",
             .outline = {{{10, 20}, {12, 20}, {12, 22}}},
             .channels = kChannelX | kChannelY | kChannelT,
             .samples = {{.x = 10, .y = 20, .t = 0}, {.x = 12, .y = 22, .t = 20}}};
  Figure figure{.id = "f-c718xa2kq9mz", .transform = {.e = 35, .f = 47},
                .scene_href = "../assets/f-c718xa2kq9mz.scene.json",
                .tikz_href = "../assets/f-c718xa2kq9mz.tikz"};
  figure.children = figure.children.push_back(immer::box<Element>(Element{ink}));
  Page page{.id = "p-c718xa", .file = "pages/0001.svg", .width = 595.28, .height = 841.89};
  LayerContent layer{.layer_id = "l-8f3kq0"};
  layer.elements = layer.elements.push_back(immer::box<Element>(Element{figure}));
  layer.elements = layer.elements.push_back(
      immer::box<Element>(Element{Bookmark{"b-27r4cq9ax6mh", {}}}));
  page.layers.push_back(layer);

  const std::string bytes = WritePage(page);
  CHECK(bytes.find("<g id=\"f-c718xa2kq9mz\" class=\"mn-figure\" transform=\"translate(35,47)\" "
                   "mn:scene=\"../assets/f-c718xa2kq9mz.scene.json\" "
                   "mn:tikz=\"../assets/f-c718xa2kq9mz.tikz\">") != std::string::npos);
  CHECK(bytes.find("<inkml:trace contextRef=\"#xyt\">10 20 0,12 22 20</inkml:trace>") !=
        std::string::npos);
  CHECK(bytes.find("d=\"M10 20l2 0 0 2Z\"") != std::string::npos);

  Page reopened = ReadPage(bytes, page.file, {layer.layer_id});
  REQUIRE_FALSE(reopened.error.has_value());
  REQUIRE(reopened.layers[0].elements.size() == 2);
  const Figure &saved = std::get<Figure>(reopened.layers[0].elements[0]->value);
  CHECK(saved.id == figure.id);
  CHECK(saved.transform == figure.transform);
  CHECK(saved.scene_href == figure.scene_href);
  CHECK(saved.tikz_href == figure.tikz_href);
  REQUIRE(saved.children.size() == 1);
  CHECK(std::get<Stroke>(saved.children[0]->value).samples == ink.samples);
  CHECK(std::get<Bookmark>(reopened.layers[0].elements[1]->value).id == "b-27r4cq9ax6mh");
  CHECK(WritePage(reopened) == bytes);
}
