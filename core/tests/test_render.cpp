// Page layout and rendering (issue #20).
#include <catch2/catch_test_macros.hpp>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <memory>

#include "editor/canvas.h"
#include "format/notebook.h"
#include "include/codec/SkCodec.h"
#include "include/codec/SkPngDecoder.h"
#include "include/core/SkBitmap.h"
#include "include/core/SkCanvas.h"
#include "include/core/SkColorSpace.h"
#include "include/core/SkData.h"
#include "include/core/SkSurface.h"
#include "layout/layout.h"
#include "document/templates.h"
#include "render/renderer.h"
#include "support/notebook_dir.h"
#include "support/session.h"

using namespace ink_engine;

namespace {

const std::string kDocuments = INK_DOCUMENTS_DIR;
const std::string kGoldens = INK_FIXTURE_DIR "/render/";

sk_sp<SkSurface> Screen(int width, int height) {
  return SkSurfaces::Raster(SkImageInfo::MakeN32Premul(width, height, SkColorSpace::MakeSRGB()));
}

SkBitmap Pixels(SkSurface *surface) {
  SkBitmap bitmap;
  bitmap.allocPixels(SkImageInfo::Make(surface->width(), surface->height(),
                                       kRGBA_8888_SkColorType, kUnpremul_SkAlphaType));
  REQUIRE(surface->readPixels(bitmap, 0, 0));
  return bitmap;
}

SkBitmap DecodePng(const std::string &path) {
  auto codec = SkPngDecoder::Decode(SkData::MakeFromFileName(path.c_str()), nullptr);
  REQUIRE(codec);
  SkBitmap bitmap;
  bitmap.allocPixels(codec->getInfo().makeColorType(kRGBA_8888_SkColorType)
                         .makeAlphaType(kUnpremul_SkAlphaType)
                         .makeColorSpace(SkColorSpace::MakeSRGB()));
  REQUIRE(codec->getPixels(bitmap.pixmap()) == SkCodec::kSuccess);
  return bitmap;
}

int ChannelDiff(uint32_t a, uint32_t b) {
  int diff = 0;
  for (int shift = 0; shift < 24; shift += 8) {
    diff = std::max(diff, std::abs(int((a >> shift) & 0xFF) - int((b >> shift) & 0xFF)));
  }
  return diff;
}

// Renders the page at `placement` alone, one pixel per pt.
SkBitmap RenderPage(Renderer &renderer, const Document &document, const PagePlacement &placement,
                    int width, int height) {
  View view{{1, 0, 0, 1, -placement.x, -placement.y}, 1, width, height};
  REQUIRE(renderer.Update(document, view, false));
  sk_sp<SkSurface> screen = Screen(width, height);
  renderer.Draw(screen->getCanvas(), nullptr, nullptr);
  return Pixels(screen.get());
}

InkPenSample Pen(double x, double y, double ms, InkPhase phase, uint32_t id) {
  return {.x = x, .y = y, .time = ms, .pressure = 0.5f, .has = INK_HAS_PRESSURE, .id = id,
          .tool = INK_TOOL_PEN, .phase = uint8_t(phase)};
}

// A horizontal stroke from (x, y) to (x + 60, y), one event per 4 samples.
std::vector<std::vector<InkPenSample>> StrokeEvents(double x, double y, uint32_t first_id) {
  std::vector<std::vector<InkPenSample>> events;
  constexpr int kSamples = 24;
  for (int i = 0; i < kSamples; ++i) {
    if (i % 4 == 0) events.emplace_back();
    InkPhase phase = i == 0 ? INK_PHASE_BEGIN : i + 1 == kSamples ? INK_PHASE_END : INK_PHASE_MOVE;
    events.back().push_back(Pen(x + i * 2.5, y + 3 * std::sin(i * 0.5), i * 4.0, phase, first_id + i));
  }
  return events;
}

}  // namespace

TEST_CASE("Listed pages have a small desk gap and center on the widest") {
  Document doc = LoadNotebook(ink_test::ReadNotebookDir(kDocuments + "/full"));
  std::vector<PagePlacement> layout = LayoutPages(doc);
  REQUIRE(layout.size() == 5);  // the unlisted page 0005.svg is not laid out
  double widest = 612;          // the Letter page 0003.svg
  CHECK(layout[0].x == (widest - 595.28) / 2);
  CHECK(layout[0].y == 0);
  CHECK(layout[1].y == 841.89 + 6);
  CHECK(layout[2].x == 0);
  CHECK(layout[2].y == 2 * (841.89 + 6));
  CHECK(layout[3].y == 2 * (841.89 + 6) + 792 + 6);
  CHECK(PageAt(layout, -50)->page == 0);
  CHECK(PageAt(layout, 841.89 - 0.1)->page == 0);
  CHECK(PageAt(layout, 841.89 + 0.1) == nullptr);
  CHECK(PageAt(layout, 841.89 + 6.1)->page == 1);
  CHECK(PageAt(layout, 1e6)->page == layout.back().page);
}

TEST_CASE("A pen-down on the second page draws on it in its page coordinates") {
  Document doc = LoadNotebook(ink_test::ReadNotebookDir(kDocuments + "/full"));
  ink_test::Session canvas(doc, 7);
  std::vector<PagePlacement> layout = LayoutPages(doc);
  size_t elements = doc.pages[1]->layers[0].elements.size();
  for (auto &event : StrokeEvents(layout[1].x + 200, layout[1].y + 50, 0)) {
    ink_input(canvas.get(), event.data(), event.size());
  }
  const Page &page = *canvas.doc().pages[1];
  REQUIRE(page.layers[0].elements.size() == elements + 1);
  const Stroke &stroke = std::get<Stroke>(page.layers[0].elements.back()->value);
  CHECK(std::abs(stroke.samples.front().x - 200) < 1e-9);
  CHECK(std::abs(stroke.samples.front().y - 50) < 1e-9);
}

namespace {

// Renders every listed page of the notebook at `dir` and compares it with
// Chromium's rendering of the saved page file, in `goldens`/<NNNN>.png.
void CheckMatchesChromium(const std::string &dir, const std::string &goldens) {
  // Per channel, 0..255. Both are Skia: lines and fills differ by a few
  // levels; the dotted template's 1.44 pt dots differ by up to 18 on sliver
  // pixels, whose coverage Chromium keeps and the engine's raster drops.
  constexpr int kTolerance = 20;
  Document doc = LoadNotebook(ink_test::ReadNotebookDir(dir));
  // The saved SVG does not mark hidden layers, so Chromium draws them all.
  for (Layer &layer : doc.notebook.layers) layer.hidden = false;
  Assets assets;
  for (const auto &[path, bytes] : ink_test::ReadAssets(dir)) {
    assets[path] = SkData::MakeWithCopy(bytes.data(), bytes.size());
  }
  Renderer renderer(nullptr, assets);
  for (const PagePlacement &placement : LayoutPages(doc)) {
    const Page &page = *doc.pages[placement.page];
    if (page.error) continue;  // never written
    std::string stem = page.file.substr(page.file.rfind('/') + 1, 4);
    INFO(goldens << "/" << stem);
    SkBitmap golden = DecodePng(goldens + "/" + stem + ".png");
    int width = int(std::floor(page.width)), height = int(std::floor(page.height));
    SkBitmap engine = RenderPage(renderer, doc, placement, width, height);
    int worst = 0, over = 0;
    for (int y = 0; y < std::min(height, golden.height()); ++y) {
      for (int x = 0; x < std::min(width, golden.width()); ++x) {
        int diff = ChannelDiff(*engine.getAddr32(x, y), *golden.getAddr32(x, y));
        worst = std::max(worst, diff);
        over += diff > kTolerance;
      }
    }
    std::printf("render %s/%s: worst channel difference %d, %d pixels over %d\n", goldens.c_str(),
                stem.c_str(), worst, over, kTolerance);
    CHECK(over == 0);
  }
}

}  // namespace

TEST_CASE("Each page renders as Chromium renders its saved SVG") {
  for (const char *name : {"full", "custom-size"}) {
    CheckMatchesChromium(kDocuments + "/" + name, kGoldens + name);
  }
}

TEST_CASE("Each built-in template's background renders as Chromium renders it") {
  for (const BuiltinTemplate &t : BuiltinTemplates()) {
    CheckMatchesChromium(std::string(INK_FIXTURE_DIR "/templates/") + t.name, kGoldens + "templates/" + t.name);
  }
}


TEST_CASE("A hidden layer is not drawn") {
  Document doc = LoadNotebook(ink_test::ReadNotebookDir(kDocuments + "/full"));
  PagePlacement page2 = LayoutPages(doc)[1];
  Assets assets;
  Renderer renderer(nullptr, assets);
  // s-secondlayer1 on layer l-notesb covers (400..430, 700..703).
  SkBitmap hidden = RenderPage(renderer, doc, page2, 595, 841);
  CHECK(*hidden.getAddr32(415, 701) == 0xFFF0FFFF);  // paper #FFFFF0, RGBA in memory
  for (Layer &layer : doc.notebook.layers) layer.hidden = false;
  SkBitmap shown = RenderPage(renderer, doc, page2, 595, 841);
  CHECK(*shown.getAddr32(415, 701) == 0xFF990099);
}

TEST_CASE("While a stroke is drawn only the dirty regions are redrawn") {
  ink_test::Session canvas(3);
  Editor &editor = canvas.canvas->editor;
  Renderer renderer(nullptr, canvas.document->assets);
  const View view{{}, 1, 596, 842};
  sk_sp<SkSurface> screen = Screen(view.width, view.height);
  auto frame = [&] {
    bool live_changed = !editor.TakeUpdatedRegion().IsEmpty();
    bool drew = renderer.Update(editor.document(), view, live_changed);
    if (!drew) return false;
    std::optional<LiveInk> live;
    if (editor.Drawing()) live = LiveInk{editor.LivePage(), editor.LiveOutline(), editor.LivePen().color};
    renderer.Draw(screen->getCanvas(), live ? &*live : nullptr, nullptr);
    return true;
  };
  auto draw = [&](double x, double y, uint32_t id) {
    for (auto &event : StrokeEvents(x, y, id)) {
      ink_input(canvas.get(), event.data(), event.size());
      REQUIRE(frame());
    }
  };

  REQUIRE(frame());
  CHECK(renderer.stats().full_redraws == 1);
  CHECK_FALSE(frame());  // nothing changed
  draw(50, 100, 0);
  draw(300, 600, 100);

  RenderStats before = renderer.stats();
  auto events = StrokeEvents(100, 300, 200);
  for (size_t i = 0; i + 1 < events.size(); ++i) {
    ink_input(canvas.get(), events[i].data(), events[i].size());
    REQUIRE(frame());
    // The live stroke is drawn over the cached content, which is untouched.
    CHECK(renderer.stats().elements_drawn == before.elements_drawn);
    CHECK(renderer.stats().redrawn_pixels == before.redrawn_pixels);
  }
  ink_input(canvas.get(), events.back().data(), events.back().size());
  REQUIRE(frame());
  const RenderStats &after = renderer.stats();
  CHECK(after.full_redraws == 1);
  CHECK(after.partial_redraws == before.partial_redraws + 1);
  CHECK(after.elements_drawn == before.elements_drawn + 1);  // only the new stroke
  // The stroke spans about 60 × 8 pt; its bounds plus the antialiasing margin.
  CHECK(after.redrawn_pixels - before.redrawn_pixels < 70 * 20);

  // The partially redrawn frame equals a full redraw of the same document.
  Renderer fresh(nullptr, canvas.document->assets);
  sk_sp<SkSurface> reference = Screen(view.width, view.height);
  REQUIRE(fresh.Update(editor.document(), view, false));
  fresh.Draw(reference->getCanvas(), nullptr, nullptr);
  SkBitmap a = Pixels(screen.get()), b = Pixels(reference.get());
  int differing = 0;
  for (int y = 0; y < view.height; ++y) {
    for (int x = 0; x < view.width; ++x) differing += *a.getAddr32(x, y) != *b.getAddr32(x, y);
  }
  CHECK(differing == 0);
}
