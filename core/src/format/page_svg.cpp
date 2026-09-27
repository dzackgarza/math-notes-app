// Page SVG read and write with pugixml. Attributes are appended in the orders
// FORMAT.md gives; pugixml keeps insertion order (pugixml manual.adoc:831).
// A deterministic writer with relative path data: Write
// usvg/svgwriter.cpp:174-209, 349-406 (styluslabs/Write 401b65d). The outline
// walk, one closed subpath per outline: google/ink
// ink/rendering/skia/native/internal/path_drawable.cc:42-91 (1b220eee).
#include "format/page_svg.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdio>
#include <map>
#include <sstream>

#include <pugixml.hpp>

#include "format/numbers.h"

namespace ink_engine {
namespace {

constexpr const char *kSvgNs = "http://www.w3.org/2000/svg";
constexpr const char *kMnNs = "https://github.com/dzackgarza/math-notes-app/ns/1";
constexpr const char *kInkmlNs = "http://www.w3.org/2003/InkML";
constexpr double kMmPerPt = 25.4 / 72;

std::string Coord(double v) { return FormatNumber(v, kCoordinatePrecision); }

// ---- small readers -------------------------------------------------------

double Num(const pugi::xml_node &node, const char *name, double fallback = 0) {
  auto value = ParseNumber(node.attribute(name).value());
  return value ? *value : fallback;
}

}  // namespace

Rgb ReadColor(std::string_view text) {
  unsigned r = 0, g = 0, b = 0;
  if (text.size() == 7 && text[0] == '#') {
    std::sscanf(std::string(text).c_str() + 1, "%02x%02x%02x", &r, &g, &b);
  }
  return {uint8_t(r), uint8_t(g), uint8_t(b)};
}

std::string WriteColor(Rgb c) {
  char buffer[8];
  std::snprintf(buffer, sizeof buffer, "#%02X%02X%02X", c.r, c.g, c.b);
  return buffer;
}

namespace {

Transform ReadTransform(std::string_view text) {
  Transform t;
  if (text.empty()) return t;
  bool matrix = text.starts_with("matrix(");
  size_t open = text.find('(');
  if (open == std::string_view::npos) return t;
  std::string_view args = text.substr(open + 1);
  std::vector<double> values;
  while (auto v = NextNumber(args)) values.push_back(*v);
  if (matrix && values.size() == 6) {
    t = {values[0], values[1], values[2], values[3], values[4], values[5]};
  } else if (!matrix && !values.empty()) {
    t.e = values[0];
    t.f = values.size() > 1 ? values[1] : 0;
  }
  return t;
}

double Rounded(double v) { return *ParseNumber(Coord(v)); }

std::string Linear(double v) { return FormatNumber(v, kMatrixPrecision); }

void AppendTransform(pugi::xml_node &node, const Transform &exact) {
  // Decide the form from the written values: translate(-0.0001,0.004) is identity.
  auto linear = [](double v) { return *ParseNumber(Linear(v)); };
  Transform t{linear(exact.a), linear(exact.b), linear(exact.c),
              linear(exact.d), Rounded(exact.e), Rounded(exact.f)};
  if (t.IsIdentity()) return;
  std::string value = t.IsTranslation()
                          ? "translate(" + Coord(t.e) + "," + Coord(t.f) + ")"
                          : "matrix(" + Linear(t.a) + "," + Linear(t.b) + "," + Linear(t.c) + "," +
                                Linear(t.d) + "," + Coord(t.e) + "," + Coord(t.f) + ")";
  node.append_attribute("transform") = value.c_str();
}

void Set(pugi::xml_node &node, const char *name, const std::string &value) {
  node.append_attribute(name) = value.c_str();
}

// ---- InkML --------------------------------------------------------------

std::string TraceFormatId(uint32_t channels) {
  std::string id;
  for (auto [channel, name] : kChannels) {
    if (channels & channel) {
      for (const char *c = name; *c; ++c) id += char(std::tolower(*c));
    }
  }
  return id;
}

int ChannelPrecision(Channel channel) {
  switch (channel) {
    case kChannelX:
    case kChannelY: return kCoordinatePrecision;
    case kChannelT: return kTimePrecision;
    default: return kAnglePrecision;
  }
}

double *ChannelValue(Sample &s, Channel channel) {
  switch (channel) {
    case kChannelX: return &s.x;
    case kChannelY: return &s.y;
    case kChannelT: return &s.t;
    case kChannelF: return &s.force;
    case kChannelOE: return &s.altitude;
    case kChannelOA: return &s.azimuth;
    case kChannelOR: return &s.roll;
  }
  return nullptr;
}

// W3C InkML §3.2 trace text: points separated by ",", channel values by a space
// (microsoft/InkMLjs inkml.js InkTrace.toInkML).
std::string WriteTrace(const Stroke &stroke) {
  std::string text;
  for (size_t i = 0; i < stroke.samples.size(); ++i) {
    if (i > 0) text += ",";
    Sample s = stroke.samples[i];
    bool first = true;
    for (auto [channel, name] : kChannels) {
      if (!(stroke.channels & channel)) continue;
      if (!first) text += " ";
      first = false;
      text += FormatNumber(*ChannelValue(s, channel), ChannelPrecision(channel));
    }
  }
  return text;
}

std::vector<Sample> ReadTrace(std::string_view text, uint32_t channels) {
  std::vector<Sample> samples;
  while (!text.empty()) {
    size_t comma = text.find(',');
    std::string_view point = text.substr(0, comma);
    text = comma == std::string_view::npos ? std::string_view() : text.substr(comma + 1);
    if (point.find_first_not_of(" \t\r\n") == std::string_view::npos) continue;
    Sample s;
    for (auto [channel, name] : kChannels) {
      if (!(channels & channel)) continue;
      if (auto v = NextNumber(point)) *ChannelValue(s, channel) = *v;
    }
    samples.push_back(s);
  }
  return samples;
}

// ---- element readers ----------------------------------------------------

struct ReadContext {
  std::map<std::string, uint32_t> trace_formats;  // xml:id -> channel set
};

Elements ReadElements(const pugi::xml_node &parent, const ReadContext &context);

bool IsShapeNode(const pugi::xml_node &node) {
  return std::string_view(node.attribute("class").value()) == "mn-shape";
}

Stroke ReadStroke(const pugi::xml_node &node, const ReadContext &context) {
  Stroke s;
  s.id = node.attribute("id").value();
  s.transform = ReadTransform(node.attribute("transform").value());
  s.fill = ReadColor(node.attribute("fill").value());
  if (auto opacity = node.attribute("fill-opacity")) s.fill_opacity = Num(node, "fill-opacity");
  s.brush = node.attribute("mn:brush").value();
  s.brush_version = int(Num(node, "mn:brush-version", 1));
  s.size = Num(node, "mn:size");
  s.time = node.attribute("mn:time").value();
  s.outline = ReadPathData(node.attribute("d").value());
  pugi::xml_node trace = node.child("metadata").child("inkml:trace");
  if (trace) {
    std::string_view ref = trace.attribute("contextRef").value();
    if (ref.starts_with('#')) ref.remove_prefix(1);
    auto format = context.trace_formats.find(std::string(ref));
    if (format != context.trace_formats.end()) s.channels = format->second;
    s.samples = ReadTrace(trace.text().get(), s.channels);
  }
  return s;
}

Shape ReadShape(const pugi::xml_node &node) {
  Shape s;
  std::string_view tag = node.name();
  s.id = node.attribute("id").value();
  s.transform = ReadTransform(node.attribute("transform").value());
  s.stroke = ReadColor(node.attribute("stroke").value());
  s.stroke_width = Num(node, "stroke-width");
  if (tag == "line") {
    s.kind = ShapeKind::kLine;
    s.points = {{Num(node, "x1"), Num(node, "y1")}, {Num(node, "x2"), Num(node, "y2")}};
  } else if (tag == "rect") {
    s.kind = ShapeKind::kRect;
    s.points = {{Num(node, "x"), Num(node, "y")}, {Num(node, "width"), Num(node, "height")}};
  } else if (tag == "ellipse") {
    s.kind = ShapeKind::kEllipse;
    s.points = {{Num(node, "cx"), Num(node, "cy")}, {Num(node, "rx"), Num(node, "ry")}};
  } else if (tag == "polygon") {
    s.kind = ShapeKind::kPolygon;
    std::string_view points = node.attribute("points").value();
    while (true) {
      auto x = NextNumber(points);
      auto y = NextNumber(points);
      if (!x || !y) break;
      s.points.push_back({*x, *y});
    }
  } else {
    s.kind = ShapeKind::kPath;
    s.path = ReadPathData(node.attribute("d").value());
  }
  return s;
}

Image ReadImage(const pugi::xml_node &node) {
  Image image;
  image.id = node.attribute("id").value();
  image.transform = ReadTransform(node.attribute("transform").value());
  image.href = node.attribute("href") ? node.attribute("href").value()
                                      : node.attribute("xlink:href").value();
  image.x = Num(node, "x");
  image.y = Num(node, "y");
  image.width = Num(node, "width");
  image.height = Num(node, "height");
  return image;
}

Text ReadText(const pugi::xml_node &node) {
  Text text;
  text.id = node.attribute("id").value();
  text.transform = ReadTransform(node.attribute("transform").value());
  text.fill = ReadColor(node.attribute("fill").value());
  text.x = Num(node, "x");
  text.y = Num(node, "y");
  if (node.attribute("font-size")) text.size = Num(node, "font-size");
  for (pugi::xml_node line : node.children("tspan")) text.lines.emplace_back(line.text().get());
  if (text.lines.empty()) text.lines.emplace_back(node.text().get());
  return text;
}

Elements ReadElements(const pugi::xml_node &parent, const ReadContext &context) {
  Elements elements;
  for (pugi::xml_node node : parent.children()) {
    std::string_view tag = node.name();
    Element element;
    if (tag == "path" && !IsShapeNode(node)) {
      element.value = ReadStroke(node, context);
    } else if (tag == "path" || tag == "line" || tag == "rect" || tag == "ellipse" ||
               tag == "polygon") {
      element.value = ReadShape(node);
    } else if (tag == "image") {
      element.value = ReadImage(node);
    } else if (tag == "text") {
      element.value = ReadText(node);
    } else if (tag == "g") {
      if (std::string_view(node.attribute("class").value()) == "mn-figure") {
        element.value = Figure{node.attribute("id").value(),
                               ReadTransform(node.attribute("transform").value()),
                               node.attribute("mn:scene").value(),
                               node.attribute("mn:tikz").value(), ReadElements(node, context)};
      } else {
        element.value = Bookmark{node.attribute("id").value(), ReadElements(node, context)};
      }
    } else if (tag == "a") {
      std::string href = node.attribute("href") ? node.attribute("href").value()
                                                : node.attribute("xlink:href").value();
      element.value = Link{href, ReadElements(node, context)};
    } else {
      continue;
    }
    elements = std::move(elements).push_back(immer::box<Element>(std::move(element)));
  }
  return elements;
}

Ruling ReadRuling(std::string_view text) {
  if (text == "lined") return Ruling::kLined;
  if (text == "grid") return Ruling::kGrid;
  if (text == "dotted") return Ruling::kDotted;
  return Ruling::kBlank;
}

const char *RulingName(Ruling ruling) {
  switch (ruling) {
    case Ruling::kLined: return "lined";
    case Ruling::kGrid: return "grid";
    case Ruling::kDotted: return "dotted";
    case Ruling::kBlank: return "blank";
  }
  return "blank";
}

Background ReadBackground(const pugi::xml_node &g) {
  Background bg;
  bg.ruling = ReadRuling(g.attribute("mn:ruling").value());
  bg.y_ruling = Num(g, "mn:y-ruling");
  bg.y_offset = Num(g, "mn:y-offset");
  bg.x_ruling = Num(g, "mn:x-ruling");
  bg.margin_left = Num(g, "mn:margin-left");
  for (pugi::xml_node node : g.children()) {
    std::string_view tag = node.name();
    if (tag == "image") {
      bg.image = ReadImage(node);
    } else if (tag == "rect") {
      bg.fill = ReadColor(node.attribute("fill").value());
    } else if (tag == "path") {
      bg.lines.push_back({ReadPathData(node.attribute("d").value()),
                          ReadColor(node.attribute("stroke").value()), Num(node, "stroke-width"),
                          std::string_view(node.attribute("stroke-linecap").value()) == "round"});
    }
  }
  return bg;
}

// ---- element writers ----------------------------------------------------

void WriteElements(pugi::xml_node &parent, const Elements &elements);

void WriteStroke(pugi::xml_node &parent, const Stroke &s) {
  pugi::xml_node node = parent.append_child("path");
  Set(node, "id", s.id);
  AppendTransform(node, s.transform);
  Set(node, "fill", WriteColor(s.fill));
  if (s.fill_opacity) Set(node, "fill-opacity", FormatNumber(*s.fill_opacity, kAnglePrecision));
  Set(node, "mn:brush", s.brush);
  Set(node, "mn:brush-version", std::to_string(s.brush_version));
  Set(node, "mn:size", Coord(s.size));
  Set(node, "mn:time", s.time);
  Set(node, "d", WritePathData(s.outline, /*closed=*/true));
  if (!s.samples.empty()) {
    pugi::xml_node trace = node.append_child("metadata").append_child("inkml:trace");
    Set(trace, "contextRef", "#" + TraceFormatId(s.channels));
    trace.text() = WriteTrace(s).c_str();
  }
}

void WriteShape(pugi::xml_node &parent, const Shape &s) {
  static constexpr const char *kTags[] = {"line", "polygon", "rect", "ellipse", "path"};
  pugi::xml_node node = parent.append_child(kTags[int(s.kind)]);
  Set(node, "id", s.id);
  Set(node, "class", "mn-shape");
  AppendTransform(node, s.transform);
  Set(node, "fill", "none");
  Set(node, "stroke", WriteColor(s.stroke));
  Set(node, "stroke-width", Coord(s.stroke_width));
  auto point = [&](size_t i) { return i < s.points.size() ? s.points[i] : Point{}; };
  switch (s.kind) {
    case ShapeKind::kLine:
      Set(node, "x1", Coord(point(0).x));
      Set(node, "y1", Coord(point(0).y));
      Set(node, "x2", Coord(point(1).x));
      Set(node, "y2", Coord(point(1).y));
      break;
    case ShapeKind::kRect:
      Set(node, "x", Coord(point(0).x));
      Set(node, "y", Coord(point(0).y));
      Set(node, "width", Coord(point(1).x));
      Set(node, "height", Coord(point(1).y));
      break;
    case ShapeKind::kEllipse:
      Set(node, "cx", Coord(point(0).x));
      Set(node, "cy", Coord(point(0).y));
      Set(node, "rx", Coord(point(1).x));
      Set(node, "ry", Coord(point(1).y));
      break;
    case ShapeKind::kPolygon: {
      std::string points;
      for (const Point &p : s.points) {
        if (!points.empty()) points += " ";
        points += Coord(p.x) + "," + Coord(p.y);
      }
      Set(node, "points", points);
      break;
    }
    case ShapeKind::kPath:
      Set(node, "d", WritePathData(s.path, /*closed=*/false));
      break;
  }
}

void WriteImage(pugi::xml_node &parent, const Image &image) {
  pugi::xml_node node = parent.append_child("image");
  if (!image.id.empty()) Set(node, "id", image.id);
  AppendTransform(node, image.transform);
  Set(node, "href", image.href);
  Set(node, "x", Coord(image.x));
  Set(node, "y", Coord(image.y));
  Set(node, "width", Coord(image.width));
  Set(node, "height", Coord(image.height));
}

void WriteText(pugi::xml_node &parent, const Text &text) {
  pugi::xml_node node = parent.append_child("text");
  Set(node, "id", text.id);
  AppendTransform(node, text.transform);
  Set(node, "x", Coord(text.x));
  Set(node, "y", Coord(text.y));
  Set(node, "fill", WriteColor(text.fill));
  Set(node, "font-family", "sans-serif");
  Set(node, "font-size", Coord(text.size));
  for (size_t i = 0; i < text.lines.size(); ++i) {
    pugi::xml_node line = node.append_child("tspan");
    Set(line, "x", Coord(text.x));
    if (i > 0) Set(line, "dy", Coord(text.size * 1.2));
    line.text() = text.lines[i].c_str();
  }
}

void WriteElements(pugi::xml_node &parent, const Elements &elements) {
  for (const auto &box : elements) {
    std::visit(
        [&](const auto &e) {
          using T = std::decay_t<decltype(e)>;
          if constexpr (std::is_same_v<T, Stroke>) {
            WriteStroke(parent, e);
          } else if constexpr (std::is_same_v<T, Shape>) {
            WriteShape(parent, e);
          } else if constexpr (std::is_same_v<T, Image>) {
            WriteImage(parent, e);
          } else if constexpr (std::is_same_v<T, Text>) {
            WriteText(parent, e);
          } else if constexpr (std::is_same_v<T, Bookmark>) {
            pugi::xml_node g = parent.append_child("g");
            Set(g, "id", e.id);
            Set(g, "class", "mn-bookmark");
            WriteElements(g, e.children);
          } else if constexpr (std::is_same_v<T, Figure>) {
            pugi::xml_node g = parent.append_child("g");
            Set(g, "id", e.id);
            Set(g, "class", "mn-figure");
            AppendTransform(g, e.transform);
            Set(g, "mn:scene", e.scene_href);
            Set(g, "mn:tikz", e.tikz_href);
            WriteElements(g, e.children);
          } else {
            pugi::xml_node a = parent.append_child("a");
            Set(a, "href", e.href);
            WriteElements(a, e.children);
          }
        },
        box->value);
  }
}

void CollectChannelSets(const Elements &elements, std::vector<uint32_t> &sets) {
  for (const auto &box : elements) {
    if (auto *s = std::get_if<Stroke>(&box->value)) {
      if (!s->samples.empty() && std::find(sets.begin(), sets.end(), s->channels) == sets.end()) {
        sets.push_back(s->channels);
      }
    } else if (auto *b = std::get_if<Bookmark>(&box->value)) {
      CollectChannelSets(b->children, sets);
    } else if (auto *f = std::get_if<Figure>(&box->value)) {
      CollectChannelSets(f->children, sets);
    } else if (auto *l = std::get_if<Link>(&box->value)) {
      CollectChannelSets(l->children, sets);
    }
  }
}

struct StringWriter : pugi::xml_writer {
  std::string out;
  void write(const void *data, size_t size) override {
    out.append(static_cast<const char *>(data), size);
  }
};

}  // namespace

std::string WritePathData(const std::vector<Polyline> &polylines, bool closed) {
  std::string d;
  for (const Polyline &line : polylines) {
    if (line.empty()) continue;
    // Deltas between rounded absolute positions, so reading the relative
    // commands back recovers the same rounded positions.
    double px = Rounded(line[0].x), py = Rounded(line[0].y);
    d += "M" + Coord(px) + " " + Coord(py);
    for (size_t i = 1; i < line.size(); ++i) {
      double x = Rounded(line[i].x), y = Rounded(line[i].y);
      d += (i == 1 ? "l" : " ") + Coord(x - px) + " " + Coord(y - py);
      px = x;
      py = y;
    }
    if (closed) d += "Z";
  }
  return d;
}

// Reads the M/m, L/l, H/h, V/v and Z/z commands that page files use.
std::vector<Polyline> ReadPathData(std::string_view d) {
  std::vector<Polyline> lines;
  double x = 0, y = 0, start_x = 0, start_y = 0;
  char command = 0;
  while (true) {
    size_t next = d.find_first_not_of(" \t\r\n,");
    if (next == std::string_view::npos) break;
    d.remove_prefix(next);
    if (std::isalpha(static_cast<unsigned char>(d[0]))) {
      command = d[0];
      d.remove_prefix(1);
      if (command == 'Z' || command == 'z') {
        x = start_x;
        y = start_y;
        continue;
      }
    }
    auto a = NextNumber(d);
    if (!a) break;
    bool relative = std::islower(static_cast<unsigned char>(command));
    char upper = char(std::toupper(static_cast<unsigned char>(command)));
    if (upper == 'H') {
      x = relative ? x + *a : *a;
    } else if (upper == 'V') {
      y = relative ? y + *a : *a;
    } else {
      auto b = NextNumber(d);
      if (!b) break;
      x = relative ? x + *a : *a;
      y = relative ? y + *b : *b;
    }
    if (upper == 'M') {
      lines.emplace_back();
      start_x = x;
      start_y = y;
      command = relative ? 'l' : 'L';  // later pairs are line-tos
    }
    if (lines.empty()) lines.emplace_back();
    lines.back().push_back({x, y});
  }
  return lines;
}

Page ReadPage(std::string_view bytes, const std::string &file,
              const std::vector<std::string> &layer_ids) {
  Page page;
  page.file = file;
  pugi::xml_document doc;
  pugi::xml_parse_result result = doc.load_buffer(bytes.data(), bytes.size());
  pugi::xml_node svg = doc.child("svg");
  if (!result || !svg) {
    page.error = result ? "no <svg> root element"
                        : std::string(result.description()) + " at offset " +
                              std::to_string(result.offset);
    return page;
  }
  page.id = svg.attribute("id").value();
  std::string_view view_box = svg.attribute("viewBox").value();
  std::vector<double> box;
  while (auto v = NextNumber(view_box)) box.push_back(*v);
  if (box.size() == 4) {
    page.width = box[2];
    page.height = box[3];
  }

  ReadContext context;
  for (pugi::xml_node format : svg.child("metadata").children("inkml:traceFormat")) {
    uint32_t channels = 0;
    for (pugi::xml_node channel : format.children("inkml:channel")) {
      for (auto [bit, name] : kChannels) {
        if (std::string_view(channel.attribute("name").value()) == name) channels |= bit;
      }
    }
    context.trace_formats[format.attribute("xml:id").value()] = channels;
  }

  std::map<std::string, Elements> by_layer;
  std::vector<std::string> extra_layers;
  for (pugi::xml_node g : svg.children("g")) {
    std::string id = g.attribute("id").value();
    if (id == "background") {
      page.background = ReadBackground(g);
      continue;
    }
    by_layer[id] = ReadElements(g, context);
    if (std::find(layer_ids.begin(), layer_ids.end(), id) == layer_ids.end()) {
      extra_layers.push_back(id);
    }
  }
  for (const std::string &id : layer_ids) page.layers.push_back({id, by_layer[id]});
  for (const std::string &id : extra_layers) page.layers.push_back({id, by_layer[id]});
  return page;
}

std::string WritePage(const Page &page) {
  pugi::xml_document doc;
  pugi::xml_node svg = doc.append_child("svg");
  Set(svg, "xmlns", kSvgNs);
  Set(svg, "xmlns:mn", kMnNs);
  Set(svg, "xmlns:inkml", kInkmlNs);
  Set(svg, "id", page.id);
  Set(svg, "width", Coord(page.width * kMmPerPt) + "mm");
  Set(svg, "height", Coord(page.height * kMmPerPt) + "mm");
  Set(svg, "viewBox", "0 0 " + Coord(page.width) + " " + Coord(page.height));

  std::vector<uint32_t> channel_sets;
  for (const LayerContent &layer : page.layers) CollectChannelSets(layer.elements, channel_sets);
  std::sort(channel_sets.begin(), channel_sets.end());
  pugi::xml_node metadata = svg.append_child("metadata");
  for (uint32_t channels : channel_sets) {
    pugi::xml_node format = metadata.append_child("inkml:traceFormat");
    Set(format, "xml:id", TraceFormatId(channels));
    for (auto [bit, name] : kChannels) {
      if (!(channels & bit)) continue;
      pugi::xml_node channel = format.append_child("inkml:channel");
      Set(channel, "name", name);
      Set(channel, "type", bit == kChannelT ? "integer" : "decimal");
      const char *units = bit == kChannelX || bit == kChannelY ? "pt"
                          : bit == kChannelT                  ? "ms"
                          : bit == kChannelF                  ? nullptr
                                                              : "rad";
      if (units) Set(channel, "units", units);
    }
  }

  const Background &bg = page.background;
  pugi::xml_node background = svg.append_child("g");
  Set(background, "id", "background");
  Set(background, "mn:ruling", RulingName(bg.ruling));
  Set(background, "mn:y-ruling", Coord(bg.y_ruling));
  Set(background, "mn:y-offset", Coord(bg.y_offset));
  Set(background, "mn:x-ruling", Coord(bg.x_ruling));
  Set(background, "mn:margin-left", Coord(bg.margin_left));
  pugi::xml_node rect = background.append_child("rect");
  Set(rect, "width", Coord(page.width));
  Set(rect, "height", Coord(page.height));
  Set(rect, "fill", WriteColor(bg.fill));
  if (bg.image) WriteImage(background, *bg.image);
  for (const RulingPath &line : bg.lines) {
    pugi::xml_node path = background.append_child("path");
    Set(path, "d", WritePathData(line.d, /*closed=*/false));
    Set(path, "fill", "none");
    Set(path, "stroke", WriteColor(line.stroke));
    Set(path, "stroke-width", Coord(line.stroke_width));
    if (line.round_caps) Set(path, "stroke-linecap", "round");
  }

  for (const LayerContent &layer : page.layers) {
    pugi::xml_node g = svg.append_child("g");
    Set(g, "id", layer.layer_id);
    WriteElements(g, layer.elements);
  }

  StringWriter writer;
  doc.save(writer, "  ", pugi::format_indent | pugi::format_no_declaration, pugi::encoding_utf8);
  return writer.out;
}

}  // namespace ink_engine
