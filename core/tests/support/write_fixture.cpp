#include "support/write_fixture.h"

#include <fstream>
#include <sstream>
#include <stdexcept>

#include <nlohmann/json.hpp>
#include <pugixml.hpp>

#include "editor/canvas.h"
#include "editor/erase.h"
#include "include/core/SkPath.h"
#include "include/utils/SkParsePath.h"

namespace ink_test {
namespace {

void Require(bool ok, const std::string &what) {
  if (!ok) throw std::runtime_error(what);
}

std::set<std::string> StrokeIds(const ink_engine::Document &document) {
  std::set<std::string> ids;
  for (const auto &box : document.pages[0]->layers[0].elements) {
    if (const auto *s = std::get_if<ink_engine::Stroke>(&box->value)) ids.insert(s->id);
  }
  return ids;
}

}  // namespace

std::vector<WriteEvent> ReadWriteTrace(const std::string &path, const std::string &until) {
  std::ifstream in(path);
  Require(in.is_open(), "cannot open " + path);
  std::vector<WriteEvent> events;
  std::string line;
  while (std::getline(in, line)) {
    std::istringstream words(line);
    std::string command;
    if (!(words >> command) || command[0] == '#') continue;
    if (command == until) break;
    if (command == "ie") {
      WriteEvent e;
      int src, mm;
      Require(bool(words >> e.x >> e.y >> e.pressure >> src >> e.ev >> mm >> e.time), line);
      events.push_back(e);
    } else if (command == "mode") {
      WriteEvent e{.kind = WriteEvent::kMode};
      Require(bool(words >> e.mode), line);
      events.push_back(e);
    } else if (command == "cmd") {
      WriteEvent e{.kind = WriteEvent::kCommand};
      Require(bool(words >> e.command), line);
      events.push_back(e);
    } else if (command == "pen") {
      WriteEvent e{.kind = WriteEvent::kPen};
      Require(bool(words >> e.argb >> e.width), line);
      events.push_back(e);
    } else if (command == "hyperref") {
      WriteEvent e{.kind = WriteEvent::kLink};
      Require(bool(words >> e.href), line);
      events.push_back(e);
    } else if (command == "clearsel") {
      events.push_back({.kind = WriteEvent::kClearSelection});
    } else if (command == "view") {
      int page;
      double x, y;
      Require(bool(words >> page >> x >> y) && page == 0, line);
    } else if (command == "cfg") {
      // The engine's ruled erase is Write's default, greedyRuledErase 1.
      std::string key;
      int value;
      Require(bool(words >> key >> value) && key == "greedyRuledErase" && value == 1,
              "unsupported trace command: " + line);
    } else {
      Require(command == "screen" || command == "props" || command == "pathrel",
              "unsupported trace command: " + line);
    }
  }
  return events;
}

WritePage ReadWritePage(const std::string &path) {
  std::ifstream in(path);
  Require(in.is_open(), "cannot open " + path);
  WritePage page;
  std::string line;
  while (std::getline(in, line)) {
    std::istringstream words(line);
    std::string command;
    if (!(words >> command) || command != "props") continue;
    double width, height, x_ruling, y_ruling, margin_left;
    Require(bool(words >> width >> height >> x_ruling >> y_ruling >> margin_left) && x_ruling == 0, line);
    page = {kWritePt * width, kWritePt * height, kWritePt * y_ruling, kWritePt * margin_left};
  }
  return page;
}

ink_engine::Document WithWritePage(ink_engine::Document document, const WritePage &from) {
  ink_engine::Page page = *document.pages[0];
  page.width = from.width;
  page.height = from.height;
  page.background = {.ruling = from.y_ruling > 0 ? ink_engine::Ruling::kLined : ink_engine::Ruling::kBlank,
                     .y_ruling = from.y_ruling, .margin_left = from.margin_left};
  document.pages = document.pages.set(0, immer::box<ink_engine::Page>(std::move(page)));
  return document;
}

WriteExpected ReadWriteExpected(const std::string &path) {
  std::ifstream in(path);
  Require(in.is_open(), "cannot open " + path);
  nlohmann::json json = nlohmann::json::parse(in);
  WriteExpected expected;
  for (const auto &e : json["pages"][0]["elements"]) {
    const auto &m = e["transform"];
    WriteElement element{.id = e["id"],
                         .transform = {m[0], m[1], m[2], m[3], kWritePt * double(m[4]),
                                       kWritePt * double(m[5])}};
    if (e.contains("penPoints")) {
      for (const auto &subpath : e["penPoints"]) {
        auto &points = element.pen_points.emplace_back();
        for (const auto &p : subpath) points.push_back({kWritePt * double(p[0]), kWritePt * double(p[1])});
      }
    }
    expected.elements.push_back(std::move(element));
  }
  for (int id : json["selected"]) expected.selected.insert(id);
  for (int id : json["deleted"]) expected.deleted.insert(id);
  return expected;
}

std::vector<std::vector<ink_engine::Point>> ReadWriteDocument(const std::string &path) {
  pugi::xml_document xml;
  Require(bool(xml.load_file(path.c_str())), "cannot parse " + path);
  pugi::xml_node page = xml.select_node("//g[starts-with(@id, 'page_')]").node();
  Require(bool(page), "no page in " + path);
  std::vector<std::vector<ink_engine::Point>> lines;
  for (pugi::xml_node node : page.children("path")) {
    if (std::string(node.attribute("class").value()) == "ruleline") continue;
    std::optional<SkPath> d = SkParsePath::FromSVGString(node.attribute("d").value());
    Require(d.has_value(), "bad path data in " + path);
    auto iter = d->iter();
    while (auto rec = iter.next()) {
      if (rec->fVerb == SkPathVerb::kMove) lines.emplace_back();
      Require(rec->fVerb == SkPathVerb::kMove || rec->fVerb == SkPathVerb::kLine,
              "a Write stroke has only lines: " + path);
      const SkPoint &p = rec->fPoints.back();
      lines.back().push_back({kWritePt * p.x(), kWritePt * p.y()});
    }
  }
  return lines;
}

ink_engine::Document WithStrokes(ink_engine::Document document,
                                 const std::vector<std::vector<ink_engine::Point>> &lines) {
  ink_engine::Page page = *document.pages[0];
  for (size_t i = 0; i < lines.size(); ++i) {
    ink_engine::Stroke stroke{.id = "s-input" + std::to_string(i), .brush = "marker",
                              .size = kWritePt, .time = "2026-01-01T00:00:00.000Z",
                              .channels = ink_engine::kChannelX | ink_engine::kChannelY |
                                          ink_engine::kChannelT};
    for (size_t k = 0; k < lines[i].size(); ++k) {
      stroke.samples.push_back({.x = lines[i][k].x, .y = lines[i][k].y, .t = 10.0 * k});
    }
    ink_engine::RebuildOutline(stroke);
    page.layers[0].elements =
        std::move(page.layers[0].elements).push_back(immer::box<ink_engine::Element>(ink_engine::Element{stroke}));
  }
  document.pages = document.pages.set(0, immer::box<ink_engine::Page>(std::move(page)));
  return document;
}

std::vector<std::string> ReplayWriteTrace(InkCanvas *canvas, const std::vector<WriteEvent> &trace) {
  ink_canvas_set_view(canvas, 1 / kWritePt, 0, 0, 1 / kWritePt, 0, 0);
  InkToolSettings marker{INK_BRUSH_MARKER, 0x000000, float(kWritePt), 1, 0, 20};
  ink_canvas_set_tool(canvas, &marker);
  ink_canvas_set_eraser(canvas, INK_ERASER_STROKE, 0);
  std::vector<std::string> drawn;
  bool erasing = false, selecting = false;
  InkPenSample last{};
  double clock = 0;
  for (const WriteEvent &e : trace) {
    if (e.kind == WriteEvent::kMode) {
      erasing = e.mode == 14 || e.mode == 16;
      ink_canvas_set_eraser(canvas, e.mode == 16 ? INK_ERASER_FREE : INK_ERASER_STROKE, erasing);
      static const std::map<int, InkSelector> kSelectors = {
          {15, INK_SELECTOR_RULED_ERASE}, {18, INK_SELECTOR_RECT},
          {19, INK_SELECTOR_RULED}, {20, INK_SELECTOR_LASSO},
          {25, INK_SELECTOR_SPACE_VERTICAL}, {27, INK_SELECTOR_SPACE_RULED}};
      selecting = kSelectors.contains(e.mode);
      ink_canvas_set_selector(canvas, selecting ? kSelectors.at(e.mode) : INK_SELECTOR_LASSO, selecting);
      continue;
    }
    if (e.kind == WriteEvent::kCommand) {
      int32_t moved, page;
      switch (e.command) {
        case 100: Require(ink_undo(canvas->document, &moved, &page) == INK_OK, "undo"); break;
        case 101: Require(ink_redo(canvas->document, &moved, &page) == INK_OK, "redo"); break;
        case 102: Require(ink_canvas_select_all(canvas, 0) == INK_OK, "select all"); break;
        case 123: Require(ink_canvas_duplicate_selection(canvas) == INK_OK, "duplicate"); break;
        default: throw std::runtime_error("unsupported trace command: cmd " + std::to_string(e.command));
      }
      continue;
    }
    if (e.kind == WriteEvent::kPen) {
      marker.rgb = e.argb & 0xFFFFFF;
      marker.size = float(kWritePt * e.width);
      ink_canvas_set_tool(canvas, &marker);
      continue;
    }
    if (e.kind == WriteEvent::kLink) {
      Require(ink_canvas_link_selection(canvas, e.href.c_str()) == INK_OK, "link");
      drawn.emplace_back();
      continue;
    }
    if (e.kind == WriteEvent::kClearSelection) {
      Require(ink_canvas_clear_selection(canvas) == INK_OK, "clear selection");
      continue;
    }
    std::set<std::string> before = StrokeIds(canvas->editor.document());
    // The coordinates of a release are ignored: it ends at the last position.
    InkPenSample s = e.ev == -1 ? last : InkPenSample{.x = e.x, .y = e.y};
    // Write's own cases give each event the time 0 (scribbletest.cpp:499):
    // Write makes a path from the positions alone. The engine models a stroke
    // from timed input, thus such events get the 10 ms step of the recorded
    // cases.
    clock = std::max(e.time, clock + 10);
    s.time = clock;
    s.pressure = float(e.pressure);
    s.tool = INK_TOOL_PEN;
    s.phase = uint8_t(e.ev == 1 ? INK_PHASE_BEGIN : e.ev == -1 ? INK_PHASE_END : INK_PHASE_MOVE);
    ink_input(canvas, &s, 1);
    last = s;
    if (e.ev != -1) continue;
    if (erasing || selecting) {
      erasing = selecting = false;
      ink_canvas_set_eraser(canvas, INK_ERASER_STROKE, 0);
      ink_canvas_set_selector(canvas, INK_SELECTOR_LASSO, 0);
      continue;
    }
    for (const std::string &id : StrokeIds(canvas->editor.document())) {
      if (!before.contains(id)) drawn.push_back(id);
    }
  }
  return drawn;
}

}  // namespace ink_test
