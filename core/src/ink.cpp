#include "ink.h"

#include <algorithm>
#include <cmath>
#include <exception>
#include <optional>
#include <set>
#include <string>

#include <nlohmann/json.hpp>

#include "editor/canvas.h"
#include "export/pdf.h"
#include "document/templates.h"
#include "format/notebook.h"
#include "format/page_svg.h"
#include "format/pens.h"
#include "geometry/affine.h"
#include "layout/layout.h"
#include "include/core/SkData.h"
#include "include/core/SkColorSpace.h"
#include "include/core/SkStream.h"
#include "include/core/SkSurface.h"
#include "include/encode/SkPngEncoder.h"

namespace {

std::string gLastError;

InkStatus Fail(InkStatus status, std::string message) {
  gLastError = std::move(message);
  return status;
}

// Runs one ABI call: a C++ exception becomes a status and a message.
template <class Body>
InkStatus Call(Body &&body) {
  try {
    return body();
  } catch (const nlohmann::json::exception &e) {
    return Fail(INK_ERROR_PARSE, e.what());
  } catch (const std::exception &e) {
    return Fail(INK_ERROR_INTERNAL, e.what());
  } catch (...) {
    return Fail(INK_ERROR_INTERNAL, "unknown exception");
  }
}

InkStatus NullArgument(const char *name) {
  return Fail(INK_ERROR_ARGUMENT, std::string(name) + " is null");
}

std::string_view Bytes(const uint8_t *bytes, size_t size) {
  return {reinterpret_cast<const char *>(bytes), size};
}

InkStatus BadPageIndex() { return Fail(INK_ERROR_ARGUMENT, "page index out of range"); }

InkStatus ParsePageSize(InkPageSize size, double width, double height, ink_engine::PageSize *page_size) {
  switch (size) {
    case INK_PAGE_A4: *page_size = std::string("A4"); return INK_OK;
    case INK_PAGE_LETTER: *page_size = std::string("Letter"); return INK_OK;
    case INK_PAGE_CUSTOM:
      if (!(width > 0 && height > 0)) return Fail(INK_ERROR_ARGUMENT, "non-positive page size");
      *page_size = std::array<double, 2>{width, height};
      return INK_OK;
    default: return Fail(INK_ERROR_ARGUMENT, "unknown page size");
  }
}

// One undo or redo step: `*page` is the page the step changed, or -1.
InkStatus Step(InkDocument *document, bool (ink_engine::DocumentHistory::*move)(), int32_t *moved,
               int32_t *page) {
  if (!document) return NullArgument("document");
  if (!moved || !page) return NullArgument("moved or page");
  ink_engine::Document before = document->history.current();
  *moved = (document->history.*move)();
  std::optional<size_t> changed = ink_engine::FirstChangedPage(before, document->history.current());
  *page = changed ? int32_t(*changed) : -1;
  return INK_OK;
}

InkStatus AttachSurface(InkDocument *document, std::unique_ptr<ink_engine::HostSurface> surface,
                        InkCanvas **out) {
  if (!surface) return Fail(INK_ERROR_GPU, "no GPU context for the surface");
  auto canvas = std::make_unique<InkCanvas>(*document);
  canvas->surface = std::move(surface);
  canvas->renderer =
      std::make_unique<ink_engine::Renderer>(canvas->surface->context(), document->assets);
  canvas->assets_seen = document->assets_version;
  *out = canvas.release();
  return INK_OK;
}

// The pen of tool settings, or an error message for a bad value.
std::optional<std::string> CheckTool(const InkToolSettings &tool) {
  if (tool.brush > INK_BRUSH_HIGHLIGHTER) return "unknown brush";
  if (!(tool.size > 0)) return "non-positive size";
  if (!(tool.opacity > 0 && tool.opacity <= 1)) return "opacity outside (0, 1]";
  return std::nullopt;
}

ink_engine::Pen ToPen(const InkToolSettings &tool) {
  uint32_t rgb = tool.rgb;
  return {.brush = InkBrush(tool.brush),
          .color = {uint8_t(rgb >> 16), uint8_t(rgb >> 8), uint8_t(rgb)},
          .size = tool.size,
          .opacity = tool.opacity};
}

// The results of the last ink_pens_* call.
struct PenFile {
  std::string json;
  std::vector<ink_engine::PenPreset> presets;
  std::vector<InkPen> pens;
};
PenFile gPenFile;

}  // namespace

extern "C" {

const char *ink_version(void) { return INK_VERSION; }

const char *ink_last_error(void) { return gLastError.c_str(); }

// ---- Documents -----------------------------------------------------------

InkStatus ink_document_create(uint64_t seed, InkDocument **out) {
  return Call([&] {
    if (!out) return NullArgument("out");
    ink_engine::IdGenerator ids(seed);
    ink_engine::Document document = ink_engine::NewNotebook(ids);
    *out = new InkDocument{ink_engine::DocumentHistory(std::move(document), seed + 1)};
    return INK_OK;
  });
}

InkStatus ink_document_create_from_template(uint64_t seed, const char *name, const uint8_t *svg,
                                            size_t size, InkPageSize page_size, double width,
                                            double height, InkDocument **out) {
  return Call([&] {
    if (!name) return NullArgument("name");
    if (!svg && size) return NullArgument("svg");
    if (!out) return NullArgument("out");
    ink_engine::PageSize parsed_size;
    InkStatus size_status = ParsePageSize(page_size, width, height, &parsed_size);
    if (size_status != INK_OK) return size_status;
    ink_engine::Page template_page = ink_engine::ReadPage(Bytes(svg, size), "pages/0001.svg", {});
    if (template_page.error) return Fail(INK_ERROR_PARSE, std::string(name) + ": " + *template_page.error);
    ink_engine::IdGenerator ids(seed);
    ink_engine::Document document = ink_engine::NewNotebook(ids, std::move(parsed_size), template_page);
    document.notebook.template_name = name;
    *out = new InkDocument{ink_engine::DocumentHistory(std::move(document), seed + 1)};
    (*out)->template_page = std::move(template_page);
    return INK_OK;
  });
}

InkStatus ink_document_load_notebook(InkDocument *document, const uint8_t *json, size_t size) {
  return Call([&] {
    if (!document) return NullArgument("document");
    if (!json && size) return NullArgument("json");
    document->history.Reset(ink_engine::ReadNotebookJson(Bytes(json, size)));
    return INK_OK;
  });
}

InkStatus ink_document_load_page(InkDocument *document, const char *file, const uint8_t *svg,
                                 size_t size) {
  return Call([&] {
    if (!document) return NullArgument("document");
    if (!file) return NullArgument("file");
    if (!svg && size) return NullArgument("svg");
    ink_engine::Document next = document->history.current();
    const ink_engine::Page &page = ink_engine::AddPage(next, file, Bytes(svg, size));
    std::optional<std::string> error = page.error;
    document->history.Reset(std::move(next));
    if (error) return Fail(INK_ERROR_PARSE, std::string(file) + ": " + *error);
    return INK_OK;
  });
}

InkStatus ink_document_load_asset(InkDocument *document, const char *path, const uint8_t *bytes,
                                  size_t size) {
  return Call([&] {
    if (!document) return NullArgument("document");
    if (!path) return NullArgument("path");
    if (!bytes && size) return NullArgument("bytes");
    document->assets[path] = SkData::MakeWithCopy(bytes, size);
    ++document->assets_version;
    return INK_OK;
  });
}

InkStatus ink_document_asset(InkDocument *document, const char *path,
                             const uint8_t **bytes, size_t *size) {
  return Call([&] {
    if (!document) return NullArgument("document");
    if (!path || !bytes || !size) return NullArgument("path, bytes or size");
    const auto found = document->assets.find(path);
    if (found == document->assets.end()) return Fail(INK_ERROR_ARGUMENT, std::string("asset is missing: ") + path);
    *bytes = static_cast<const uint8_t *>(found->second->data());
    *size = found->second->size();
    return INK_OK;
  });
}

InkStatus ink_document_dirty_files(InkDocument *document, const InkFile **files, size_t *count) {
  return Call([&] {
    if (!document) return NullArgument("document");
    if (!files || !count) return NullArgument("files");
    const ink_engine::DocumentHistory &history = document->history;
    ink_engine::NotebookFiles changed = ink_engine::ChangedFiles(history.current(), history.saved());
    const std::set<std::string> figure_assets = ink_engine::FigureAssetPaths(history.current());
    for (const auto &[path, bytes] : document->new_assets) {
      if (!path.starts_with("assets/f-") || figure_assets.contains(path)) changed[path] = bytes;
    }
    document->dirty.assign(changed.begin(), changed.end());
    document->dirty_removed = ink_engine::RemovedFiles(history.current(), history.saved());
    document->dirty_view.clear();
    for (const auto &[path, bytes] : document->dirty) {
      document->dirty_view.push_back({path.c_str(), reinterpret_cast<const uint8_t *>(bytes.data()),
                                      bytes.size(), INK_FILE_WRITE});
    }
    for (const std::string &path : document->dirty_removed) {
      document->dirty_view.push_back({path.c_str(), nullptr, 0, INK_FILE_DELETE});
    }
    *files = document->dirty_view.data();
    *count = document->dirty_view.size();
    return INK_OK;
  });
}

InkStatus ink_document_mark_saved(InkDocument *document) {
  return Call([&] {
    if (!document) return NullArgument("document");
    document->history.MarkSaved();
    document->new_assets.clear();
    return INK_OK;
  });
}

InkStatus ink_document_content_size(InkDocument *document, double *width, double *height) {
  return Call([&] {
    if (!document) return NullArgument("document");
    if (!width || !height) return NullArgument("width or height");
    std::vector<ink_engine::PagePlacement> layout =
        ink_engine::LayoutPages(document->history.current());
    *width = 0;
    for (const auto &page : layout) *width = std::max(*width, page.width);
    *height = layout.empty() ? 0 : layout.back().y + layout.back().height;
    return INK_OK;
  });
}

// ---- Pages and templates -------------------------------------------------

InkStatus ink_document_page_count(InkDocument *document, size_t *count) {
  return Call([&] {
    if (!document) return NullArgument("document");
    if (!count) return NullArgument("count");
    *count = ink_engine::ListedPageCount(document->history.current());
    return INK_OK;
  });
}

InkStatus ink_document_insert_page(InkDocument *document, size_t index) {
  return Call([&] {
    if (!document) return NullArgument("document");
    ink_engine::DocumentHistory &history = document->history;
    if (index > ink_engine::ListedPageCount(history.current())) return BadPageIndex();
    history.Push(ink_engine::InsertPage(history.current(), index, history.ids(),
                                        document->template_page));
    return INK_OK;
  });
}

InkStatus ink_document_delete_page(InkDocument *document, size_t index) {
  return Call([&] {
    if (!document) return NullArgument("document");
    ink_engine::DocumentHistory &history = document->history;
    if (index >= ink_engine::ListedPageCount(history.current())) return BadPageIndex();
    history.Push(ink_engine::DeletePage(history.current(), index));
    return INK_OK;
  });
}

InkStatus ink_document_move_page(InkDocument *document, size_t from, size_t to) {
  return Call([&] {
    if (!document) return NullArgument("document");
    ink_engine::DocumentHistory &history = document->history;
    size_t count = ink_engine::ListedPageCount(history.current());
    if (from >= count || to >= count) return BadPageIndex();
    if (from != to) history.Push(ink_engine::MovePage(history.current(), from, to));
    return INK_OK;
  });
}

InkStatus ink_document_set_page_size(InkDocument *document, InkPageSize size, double width,
                                     double height) {
  return Call([&] {
    if (!document) return NullArgument("document");
    ink_engine::PageSize page_size;
    InkStatus size_status = ParsePageSize(size, width, height, &page_size);
    if (size_status != INK_OK) return size_status;
    ink_engine::DocumentHistory &history = document->history;
    if (history.current().notebook.page_size == page_size) return INK_OK;
    history.Push(ink_engine::SetPageSize(history.current(), std::move(page_size)));
    return INK_OK;
  });
}

InkStatus ink_document_set_template(InkDocument *document, const char *name, const uint8_t *svg,
                                    size_t size) {
  return Call([&] {
    if (!document) return NullArgument("document");
    if (!name) return NullArgument("name");
    if (!svg && size) return NullArgument("svg");
    ink_engine::Page page = ink_engine::ReadPage(Bytes(svg, size), "pages/0001.svg", {});
    if (page.error) return Fail(INK_ERROR_PARSE, std::string(name) + ": " + *page.error);
    document->template_page = std::move(page);
    ink_engine::DocumentHistory &history = document->history;
    if (history.current().notebook.template_name != name) {
      ink_engine::Document next = history.current();
      next.notebook.template_name = name;
      history.Push(std::move(next));
    }
    return INK_OK;
  });
}

InkStatus ink_builtin_template_count(size_t *count) {
  return Call([&] {
    if (!count) return NullArgument("count");
    *count = ink_engine::BuiltinTemplates().size();
    return INK_OK;
  });
}

InkStatus ink_builtin_template_name(size_t index, const char **name) {
  return Call([&] {
    if (!name) return NullArgument("name");
    const auto &templates = ink_engine::BuiltinTemplates();
    if (index >= templates.size()) return Fail(INK_ERROR_ARGUMENT, "no such built-in template");
    *name = templates[index].name;
    return INK_OK;
  });
}

InkStatus ink_builtin_template_create(const char *name, uint64_t seed, InkDocument **out) {
  return Call([&] {
    if (!name) return NullArgument("name");
    if (!out) return NullArgument("out");
    ink_engine::IdGenerator ids(seed);
    std::optional<ink_engine::Document> document = ink_engine::BuiltinTemplateNotebook(name, ids);
    if (!document) return Fail(INK_ERROR_ARGUMENT, std::string("no built-in template ") + name);
    *out = new InkDocument{ink_engine::DocumentHistory(std::move(*document), seed + 1)};
    return INK_OK;
  });
}

InkStatus ink_document_free(InkDocument *document) {
  return Call([&] {
    delete document;
    return INK_OK;
  });
}

// ---- Canvases ------------------------------------------------------------

#ifdef __EMSCRIPTEN__
InkStatus ink_canvas_create_webgl(InkDocument *document, const char *selector, InkCanvas **out) {
  return Call([&] {
    if (!document) return NullArgument("document");
    if (!selector) return NullArgument("selector");
    if (!out) return NullArgument("out");
    return AttachSurface(document, ink_engine::MakeWebGLSurface(selector), out);
  });
}
#endif

#ifdef __APPLE__
InkStatus ink_canvas_create_metal(InkDocument *document, void *device, void *queue, void *layer,
                                  InkCanvas **out) {
  return Call([&] {
    if (!document) return NullArgument("document");
    if (!device || !queue || !layer) return NullArgument("device, queue or layer");
    if (!out) return NullArgument("out");
    return AttachSurface(document, ink_engine::MakeMetalSurface(device, queue, layer), out);
  });
}
#endif

InkStatus ink_canvas_set_view(InkCanvas *canvas, double a, double b, double c, double d, double e,
                              double f) {
  return Call([&] {
    if (!canvas) return NullArgument("canvas");
    if (a * d - b * c == 0) return Fail(INK_ERROR_ARGUMENT, "the view transform is singular");
    canvas->editor.SetView({a, b, c, d, e, f});
    return INK_OK;
  });
}

InkStatus ink_canvas_set_surface_size(InkCanvas *canvas, int32_t width, int32_t height,
                                      float pixel_ratio) {
  return Call([&] {
    if (!canvas) return NullArgument("canvas");
    if (width < 0 || height < 0 || !(pixel_ratio > 0)) {
      return Fail(INK_ERROR_ARGUMENT, "negative surface size or non-positive pixel ratio");
    }
    canvas->width = width;
    canvas->height = height;
    canvas->pixel_ratio = pixel_ratio;
    return INK_OK;
  });
}

InkStatus ink_canvas_set_tool(InkCanvas *canvas, const InkToolSettings *tool) {
  return Call([&] {
    if (!canvas) return NullArgument("canvas");
    if (!tool) return NullArgument("tool");
    if (auto error = CheckTool(*tool)) return Fail(INK_ERROR_ARGUMENT, *error);
    canvas->editor.SetPen(ToPen(*tool));
    return INK_OK;
  });
}

InkStatus ink_canvas_figure_begin(InkCanvas *canvas, size_t page, size_t layer) {
  return Call([&] {
    if (!canvas) return NullArgument("canvas");
    if (!canvas->editor.StartFigureCapture(page, layer)) {
      return Fail(INK_ERROR_ARGUMENT, "drawing mode needs an editable page and no active gesture");
    }
    return INK_OK;
  });
}

InkStatus ink_canvas_figure_scene(InkCanvas *canvas, const uint8_t **json, size_t *size) {
  return Call([&] {
    if (!canvas) return NullArgument("canvas");
    if (!json || !size) return NullArgument("json or size");
    const auto strokes = canvas->editor.CapturedStrokes();
    if (!strokes) return Fail(INK_ERROR_ARGUMENT, "drawing mode capture is not ready");
    nlohmann::ordered_json scene = {
        {"version", 1}, {"nextId", strokes->size() + 1},
        {"objects", nlohmann::ordered_json::array()}, {"selectedId", nullptr}};
    size_t index = 1;
    for (const ink_engine::Stroke &stroke : *strokes) {
      nlohmann::ordered_json ink = nlohmann::ordered_json::array();
      nlohmann::ordered_json points = nlohmann::ordered_json::array();
      for (const ink_engine::Sample &sample : stroke.samples) {
        ink_engine::Point point = ink_engine::Apply(stroke.transform, {sample.x, sample.y});
        ink.push_back({{"x", point.x}, {"y", point.y}, {"t", sample.t},
                       {"force", sample.force}, {"altitude", sample.altitude},
                       {"azimuth", sample.azimuth}, {"roll", sample.roll}});
        points.push_back({{"x", point.x}, {"y", point.y}});
      }
      if (points.empty()) return Fail(INK_ERROR_INTERNAL, "captured stroke has no ink samples");
      scene["objects"].push_back({{"id", "o" + std::to_string(index++)}, {"ink", ink},
                                   {"geometry", {{"kind", "rawStroke"}, {"points", points}}}});
    }
    canvas->figure_scene = scene.dump(2) + "\n";
    *json = reinterpret_cast<const uint8_t *>(canvas->figure_scene.data());
    *size = canvas->figure_scene.size();
    return INK_OK;
  });
}

InkStatus ink_canvas_figure_complete(InkCanvas *canvas, const uint8_t *scene, size_t scene_size,
                                     const uint8_t *tikz, size_t tikz_size,
                                     const uint8_t **figure_id, size_t *id_size) {
  return Call([&] {
    if (!canvas) return NullArgument("canvas");
    if ((!scene && scene_size) || (!tikz && tikz_size)) return NullArgument("scene or tikz");
    if (!figure_id || !id_size) return NullArgument("figure_id or id_size");
    const auto strokes = canvas->editor.CapturedStrokes();
    if (!strokes) return Fail(INK_ERROR_ARGUMENT, "drawing mode capture is not ready");
    if (!strokes->empty()) {
      if (!scene || !tikz || !tikz_size) {
        return Fail(INK_ERROR_ARGUMENT, "nonempty figure needs scene and TikZ source");
      }
      const nlohmann::json parsed = nlohmann::json::parse(Bytes(scene, scene_size));
      if (!parsed.is_object() || parsed.value("version", 0) != 1 ||
          !parsed.contains("objects") || !parsed["objects"].is_array() ||
          parsed["objects"].size() != strokes->size()) {
        return Fail(INK_ERROR_ARGUMENT, "scene does not match captured ink");
      }
    }
    const auto figure = canvas->editor.CompleteFigureCapture();
    canvas->figure_id = figure ? figure->id : "";
    if (figure) {
      InkDocument &document = *canvas->document;
      const std::string scene_path = "assets/" + figure->id + ".scene.json";
      const std::string tikz_path = "assets/" + figure->id + ".tikz";
      document.new_assets[scene_path] = std::string(Bytes(scene, scene_size));
      document.new_assets[tikz_path] = std::string(Bytes(tikz, tikz_size));
      document.assets[scene_path] = SkData::MakeWithCopy(scene, scene_size);
      document.assets[tikz_path] = SkData::MakeWithCopy(tikz, tikz_size);
      ++document.assets_version;
    }
    *figure_id = reinterpret_cast<const uint8_t *>(canvas->figure_id.data());
    *id_size = canvas->figure_id.size();
    return INK_OK;
  });
}

InkStatus ink_canvas_selected_figure(InkCanvas *canvas, const uint8_t **id, size_t *size) {
  return Call([&] {
    if (!canvas) return NullArgument("canvas");
    if (!id || !size) return NullArgument("id or size");
    canvas->figure_id.clear();
    const ink_engine::Selection *selection = canvas->editor.CurrentSelection();
    if (selection && selection->items.size() == 1) {
      const ink_engine::ElementRef &item = selection->items[0];
      const ink_engine::Element &element =
          *selection->value->layers[item.layer].elements[item.index];
      if (const auto *figure = std::get_if<ink_engine::Figure>(&element.value)) {
        canvas->figure_id = figure->id;
      }
    }
    *id = reinterpret_cast<const uint8_t *>(canvas->figure_id.data());
    *size = canvas->figure_id.size();
    return INK_OK;
  });
}

InkStatus ink_pens_default(const uint8_t **json, size_t *size) {
  return Call([&] {
    if (!json || !size) return NullArgument("json or size");
    gPenFile.json = ink_engine::WritePens(ink_engine::DefaultPens());
    *json = reinterpret_cast<const uint8_t *>(gPenFile.json.data());
    *size = gPenFile.json.size();
    return INK_OK;
  });
}

InkStatus ink_pens_read(const uint8_t *json, size_t size, const InkPen **pens, size_t *count) {
  return Call([&] {
    if (!json || !pens || !count) return NullArgument("json, pens or count");
    gPenFile.presets = ink_engine::ReadPens(Bytes(json, size));
    gPenFile.pens.clear();
    for (const ink_engine::PenPreset &p : gPenFile.presets) {
      InkToolSettings tool{.brush = uint32_t(ink_engine::BrushFromName(p.brush)),
                           .rgb = uint32_t(p.color.r) << 16 | uint32_t(p.color.g) << 8 | p.color.b,
                           .size = float(p.size),
                           .opacity = float(p.opacity)};
      if (auto error = CheckTool(tool)) return Fail(INK_ERROR_PARSE, "pen " + p.id + ": " + *error);
      gPenFile.pens.push_back({p.id.c_str(), p.name.c_str(), tool});
    }
    *pens = gPenFile.pens.data();
    *count = gPenFile.pens.size();
    return INK_OK;
  });
}

InkStatus ink_pens_write(const InkPen *pens, size_t count, const uint8_t **json, size_t *size) {
  return Call([&] {
    if ((!pens && count) || !json || !size) return NullArgument("pens, json or size");
    std::vector<ink_engine::PenPreset> presets;
    for (size_t i = 0; i < count; ++i) {
      if (!pens[i].id || !pens[i].name) return NullArgument("pen id or name");
      if (auto error = CheckTool(pens[i].tool)) return Fail(INK_ERROR_ARGUMENT, *error);
      ink_engine::Pen pen = ToPen(pens[i].tool);
      presets.push_back({.id = pens[i].id, .name = pens[i].name,
                         .brush = ink_engine::BrushName(pen.brush), .color = pen.color,
                         .opacity = pen.opacity, .size = pen.size});
    }
    gPenFile.json = ink_engine::WritePens(presets);
    *json = reinterpret_cast<const uint8_t *>(gPenFile.json.data());
    *size = gPenFile.json.size();
    return INK_OK;
  });
}

InkStatus ink_canvas_set_eraser(InkCanvas *canvas, InkEraser kind, int32_t active) {
  return Call([&] {
    if (!canvas) return NullArgument("canvas");
    if (kind != INK_ERASER_STROKE && kind != INK_ERASER_FREE) {
      return Fail(INK_ERROR_ARGUMENT, "unknown eraser");
    }
    canvas->editor.SetEraser(kind, active != 0);
    return INK_OK;
  });
}

InkStatus ink_canvas_set_selector(InkCanvas *canvas, InkSelector kind, int32_t active) {
  return Call([&] {
    if (!canvas) return NullArgument("canvas");
    if (kind != INK_SELECTOR_LASSO && kind != INK_SELECTOR_RECT) {
      return Fail(INK_ERROR_ARGUMENT, "unknown selector");
    }
    canvas->editor.SetSelector(kind, active != 0);
    return INK_OK;
  });
}

InkStatus ink_canvas_selection(InkCanvas *canvas, InkSelectionInfo *out) {
  return Call([&] {
    if (!canvas) return NullArgument("canvas");
    if (!out) return NullArgument("out");
    *out = {.count = 0, .page = -1};
    const ink_engine::Selection *selection = canvas->editor.CurrentSelection();
    if (!selection) return INK_OK;
    std::vector<ink_engine::PagePlacement> layout =
        ink_engine::LayoutPages(canvas->document->history.current());
    auto placement = std::find_if(layout.begin(), layout.end(),
                                  [&](const auto &p) { return p.page == selection->page; });
    if (placement == layout.end()) return INK_OK;
    const ink_engine::Rect &r = selection->rect;
    const ink_engine::Transform &v = canvas->editor.view();
    ink_engine::Point a = ink_engine::Apply(v, {placement->x + r.left, placement->y + r.top});
    ink_engine::Point b = ink_engine::Apply(v, {placement->x + r.right, placement->y + r.bottom});
    *out = {.count = uint32_t(selection->items.size()),
            .page = int32_t(selection->page),
            .x = std::min(a.x, b.x),
            .y = std::min(a.y, b.y),
            .width = std::abs(b.x - a.x),
            .height = std::abs(b.y - a.y)};
    return INK_OK;
  });
}

InkStatus ink_canvas_select_all(InkCanvas *canvas, size_t index) {
  return Call([&] {
    if (!canvas) return NullArgument("canvas");
    if (index >= ink_engine::ListedPageCount(canvas->document->history.current())) {
      return BadPageIndex();
    }
    canvas->editor.SelectAll(index);
    return INK_OK;
  });
}

InkStatus ink_canvas_clear_selection(InkCanvas *canvas) {
  return Call([&] {
    if (!canvas) return NullArgument("canvas");
    canvas->editor.ClearSelection();
    return INK_OK;
  });
}

InkStatus ink_canvas_delete_selection(InkCanvas *canvas) {
  return Call([&] {
    if (!canvas) return NullArgument("canvas");
    canvas->editor.DeleteSelection();
    return INK_OK;
  });
}

InkStatus ink_canvas_copy_selection(InkCanvas *canvas, int32_t cut, const uint8_t **svg,
                                    size_t *size) {
  return Call([&] {
    if (!canvas) return NullArgument("canvas");
    if (!svg || !size) return NullArgument("svg or size");
    canvas->clipboard = canvas->editor.CopySelection(cut != 0, canvas->document->assets);
    *svg = reinterpret_cast<const uint8_t *>(canvas->clipboard.data());
    *size = canvas->clipboard.size();
    return INK_OK;
  });
}

InkStatus ink_canvas_paste(InkCanvas *canvas, const uint8_t *svg, size_t size, double x,
                           double y) {
  return Call([&] {
    if (!canvas) return NullArgument("canvas");
    if (!svg && size) return NullArgument("svg");
    InkDocument &document = *canvas->document;
    ink_engine::NotebookFiles added;
    if (!canvas->editor.Paste(Bytes(svg, size), x, y, canvas->width / canvas->pixel_ratio,
                              canvas->height / canvas->pixel_ratio, document.assets, added)) {
      return Fail(INK_ERROR_PARSE, "the clipboard text is not a page SVG");
    }
    if (!added.empty()) {
      document.new_assets.insert(added.begin(), added.end());
      ++document.assets_version;
    }
    return INK_OK;
  });
}

InkStatus ink_canvas_duplicate_selection(InkCanvas *canvas) {
  return Call([&] {
    if (!canvas) return NullArgument("canvas");
    InkDocument &document = *canvas->document;
    ink_engine::NotebookFiles added;
    canvas->editor.DuplicateSelection(document.assets, added);
    if (!added.empty()) {
      document.new_assets.insert(added.begin(), added.end());
      ++document.assets_version;
    }
    return INK_OK;
  });
}

InkStatus ink_canvas_insert_text(InkCanvas *canvas, const uint8_t *utf8, size_t size,
                                 double x, double y) {
  return Call([&] {
    if (!canvas) return NullArgument("canvas");
    if (!utf8 && size) return NullArgument("utf8");
    if (!canvas->editor.InsertText(Bytes(utf8, size), x, y)) {
      return Fail(INK_ERROR_ARGUMENT, "text is empty or the point is outside an editable page");
    }
    return INK_OK;
  });
}

InkStatus ink_canvas_select_text_at(InkCanvas *canvas, double x, double y, int32_t *found) {
  return Call([&] {
    if (!canvas) return NullArgument("canvas");
    if (!found) return NullArgument("found");
    *found = canvas->editor.SelectTextAt(x, y);
    return INK_OK;
  });
}

InkStatus ink_canvas_selected_text(InkCanvas *canvas, const uint8_t **utf8, size_t *size) {
  return Call([&] {
    if (!canvas) return NullArgument("canvas");
    if (!utf8 || !size) return NullArgument("utf8 or size");
    canvas->selected_text = canvas->editor.SelectedText().value_or("");
    *utf8 = reinterpret_cast<const uint8_t *>(canvas->selected_text.data());
    *size = canvas->selected_text.size();
    return INK_OK;
  });
}

InkStatus ink_canvas_set_selected_text(InkCanvas *canvas, const uint8_t *utf8, size_t size) {
  return Call([&] {
    if (!canvas) return NullArgument("canvas");
    if (!utf8 && size) return NullArgument("utf8");
    if (!canvas->editor.SetSelectedText(Bytes(utf8, size))) {
      return Fail(INK_ERROR_ARGUMENT, "no text box is selected or text is empty");
    }
    return INK_OK;
  });
}

InkStatus ink_canvas_set_utc_offset(InkCanvas *canvas, double utc_minus_host_ms) {
  return Call([&] {
    if (!canvas) return NullArgument("canvas");
    canvas->editor.SetUtcOffset(utc_minus_host_ms);
    return INK_OK;
  });
}

InkStatus ink_canvas_page_at(InkCanvas *canvas, double x, double y, int32_t *page) {
  return Call([&] {
    if (!canvas) return NullArgument("canvas");
    if (!page) return NullArgument("page");
    ink_engine::Point at = ink_engine::ToContent(canvas->editor.view(), x, y);
    auto contains = [&](const ink_engine::PagePlacement &p) {
      return at.x >= p.x && at.x <= p.x + p.width && at.y >= p.y && at.y <= p.y + p.height;
    };
    std::vector<ink_engine::PagePlacement> layout =
        ink_engine::LayoutPages(canvas->document->history.current());
    *page = -1;
    for (size_t i = 0; i < layout.size(); ++i) {
      if (contains(layout[i])) *page = int32_t(i);
    }
    return INK_OK;
  });
}

InkStatus ink_canvas_free(InkCanvas *canvas) {
  return Call([&] {
    delete canvas;
    return INK_OK;
  });
}

InkStatus ink_input(InkCanvas *canvas, const InkPenSample *samples, size_t count) {
  return Call([&] {
    if (!canvas) return NullArgument("canvas");
    if (!samples && count) return NullArgument("samples");
    canvas->editor.Input(samples, count);
    if (canvas->editor.FigureCaptureStatus() ==
        ink_engine::Editor::FigureCaptureError::kCrossPageInput) {
      canvas->editor.AcknowledgeFigureCaptureError();
      return Fail(INK_ERROR_ARGUMENT, "drawing mode ink must stay on one page");
    }
    return INK_OK;
  });
}

InkStatus ink_input_update(InkCanvas *canvas, const InkPenSample *samples, size_t count) {
  return Call([&] {
    if (!canvas) return NullArgument("canvas");
    if (!samples && count) return NullArgument("samples");
    canvas->editor.InputUpdate(samples, count);
    return INK_OK;
  });
}

// ---- Frame and history ---------------------------------------------------

InkStatus ink_render(InkCanvas *canvas, int32_t *drew) {
  return Call([&] {
    if (!canvas) return NullArgument("canvas");
    if (!drew) return NullArgument("drew");
    *drew = 0;
    if (canvas->width <= 0 || canvas->height <= 0) return INK_OK;
    ink_engine::Editor &editor = canvas->editor;
    if (canvas->assets_seen != canvas->document->assets_version) {
      canvas->renderer->Invalidate();
      canvas->assets_seen = canvas->document->assets_version;
    }
    bool drawing = editor.Drawing();
    bool live_changed = !editor.TakeUpdatedRegion().IsEmpty() || drawing != canvas->was_drawing;
    live_changed = editor.TakeOverlayChanged() || live_changed;
    canvas->was_drawing = drawing;
    ink_engine::View view{editor.view(), canvas->pixel_ratio, canvas->width, canvas->height};
    if (!canvas->renderer->Update(editor.Shown(), view, live_changed)) return INK_OK;
    SkSurface *screen = canvas->surface->BeginFrame(canvas->width, canvas->height);
    if (!screen) return Fail(INK_ERROR_GPU, "the host surface gave no frame");
    std::optional<ink_engine::LiveInk> live;
    if (drawing) {
      live = {editor.LivePage(), editor.LiveOutline(), editor.LivePen().color,
              editor.LivePen().opacity};
    }
    std::optional<ink_engine::SelectionOverlay> overlay = editor.Overlay();
    canvas->renderer->Draw(screen->getCanvas(), live ? &*live : nullptr, overlay ? &*overlay : nullptr);
    canvas->surface->EndFrame();
    *drew = 1;
    return INK_OK;
  });
}

InkStatus ink_undo(InkDocument *document, int32_t *moved, int32_t *page) {
  return Call([&] { return Step(document, &ink_engine::DocumentHistory::Undo, moved, page); });
}

InkStatus ink_redo(InkDocument *document, int32_t *moved, int32_t *page) {
  return Call([&] { return Step(document, &ink_engine::DocumentHistory::Redo, moved, page); });
}

InkStatus ink_document_page_rect(InkDocument *document, size_t index, double *x, double *y,
                                 double *width, double *height) {
  return Call([&] {
    if (!document) return NullArgument("document");
    if (!x || !y || !width || !height) return NullArgument("rectangle");
    std::vector<ink_engine::PagePlacement> layout =
        ink_engine::LayoutPages(document->history.current());
    if (index >= layout.size()) return BadPageIndex();
    const ink_engine::PagePlacement &p = layout[index];
    *x = p.x, *y = p.y, *width = p.width, *height = p.height;
    return INK_OK;
  });
}

InkStatus ink_document_page_png(InkDocument *document, size_t index, int32_t width,
                                const uint8_t **png, size_t *size) {
  return Call([&] {
    if (!document) return NullArgument("document");
    if (!png || !size) return NullArgument("png or size");
    if (width <= 0) return Fail(INK_ERROR_ARGUMENT, "non-positive width");
    const ink_engine::Document &current = document->history.current();
    std::vector<ink_engine::PagePlacement> layout = ink_engine::LayoutPages(current);
    if (index >= layout.size()) return BadPageIndex();
    const ink_engine::PagePlacement &p = layout[index];
    // The page alone in a raster view, as test_render.cpp's RenderPage draws
    // it, scaled to `width` pixels.
    double scale = width / p.width;
    int height = std::max(1, int(std::lround(p.height * scale)));
    ink_engine::View view{{scale, 0, 0, scale, -p.x * scale, -p.y * scale}, 1, width, height};
    ink_engine::Renderer renderer(nullptr, document->assets);
    renderer.Update(current, view, false);
    sk_sp<SkSurface> surface =
        SkSurfaces::Raster(SkImageInfo::MakeN32Premul(width, height, SkColorSpace::MakeSRGB()));
    renderer.Draw(surface->getCanvas(), nullptr, nullptr);
    SkPixmap pixels;
    if (!surface->peekPixels(&pixels)) return Fail(INK_ERROR_INTERNAL, "no raster pixels");
    SkDynamicMemoryWStream out;
    if (!SkPngEncoder::Encode(&out, pixels, {})) {
      return Fail(INK_ERROR_INTERNAL, "PNG encoding failed");
    }
    document->png.resize(out.bytesWritten());
    out.copyTo(document->png.data());
    *png = reinterpret_cast<const uint8_t *>(document->png.data());
    *size = document->png.size();
    return INK_OK;
  });
}

InkStatus ink_export_pdf(InkDocument *document, const char *title,
                         const InkPdfExportSpec *spec, const uint8_t **pdf, size_t *size) {
  return Call([&] {
    if (!document) return NullArgument("document");
    if (!title) return NullArgument("title");
    if (!spec || !pdf || !size) return NullArgument("spec, pdf or size");
    if (!*title) return Fail(INK_ERROR_ARGUMENT, "empty PDF title");
    if (spec->include_links) return Fail(INK_ERROR_ARGUMENT, "PDF link annotations are not supported");
    const ink_engine::Document &current = document->history.current();
    if (!spec->page_count || spec->first_page >= current.pages.size() ||
        spec->page_count > current.pages.size() - spec->first_page) {
      return Fail(INK_ERROR_ARGUMENT, "PDF page range out of bounds");
    }
    for (size_t index = spec->first_page; index < spec->first_page + spec->page_count; ++index) {
      const ink_engine::Page &page = *current.pages[index];
      if (page.error) return Fail(INK_ERROR_PARSE, page.file + ": " + *page.error);
      if (!(page.width > 0 && page.height > 0)) {
        return Fail(INK_ERROR_ARGUMENT, page.file + ": non-positive page size");
      }
    }
    if (!ink_engine::ExportPdf(current, document->assets, title, spec->first_page,
                               spec->page_count, spec->include_hidden_layers != 0,
                               &document->pdf)) {
      return Fail(INK_ERROR_INTERNAL, "PDF export failed");
    }
    *pdf = reinterpret_cast<const uint8_t *>(document->pdf.data());
    *size = document->pdf.size();
    return INK_OK;
  });
}

// ---- Layout check --------------------------------------------------------

InkStatus ink_struct_layout(InkStruct which, uint32_t *out, size_t capacity, size_t *count) {
  return Call([&] {
    if (!out || !count) return NullArgument("out");
    std::vector<size_t> layout;
    switch (which) {
      case INK_STRUCT_PEN_SAMPLE:
        layout = {sizeof(InkPenSample),
                  offsetof(InkPenSample, x),
                  offsetof(InkPenSample, y),
                  offsetof(InkPenSample, time),
                  offsetof(InkPenSample, pressure),
                  offsetof(InkPenSample, altitude),
                  offsetof(InkPenSample, azimuth),
                  offsetof(InkPenSample, roll),
                  offsetof(InkPenSample, hover_height),
                  offsetof(InkPenSample, buttons),
                  offsetof(InkPenSample, has),
                  offsetof(InkPenSample, id),
                  offsetof(InkPenSample, tool),
                  offsetof(InkPenSample, phase),
                  offsetof(InkPenSample, predicted),
                  offsetof(InkPenSample, reserved)};
        break;
      case INK_STRUCT_TOOL_SETTINGS:
        layout = {sizeof(InkToolSettings), offsetof(InkToolSettings, brush),
                  offsetof(InkToolSettings, rgb), offsetof(InkToolSettings, size),
                  offsetof(InkToolSettings, opacity)};
        break;
      case INK_STRUCT_FILE:
        layout = {sizeof(InkFile), offsetof(InkFile, path), offsetof(InkFile, bytes),
                  offsetof(InkFile, size), offsetof(InkFile, kind)};
        break;
      case INK_STRUCT_SELECTION_INFO:
        layout = {sizeof(InkSelectionInfo),        offsetof(InkSelectionInfo, count),
                  offsetof(InkSelectionInfo, page),  offsetof(InkSelectionInfo, x),
                  offsetof(InkSelectionInfo, y),     offsetof(InkSelectionInfo, width),
                  offsetof(InkSelectionInfo, height)};
        break;
      case INK_STRUCT_PEN:
        layout = {sizeof(InkPen), offsetof(InkPen, id), offsetof(InkPen, name),
                  offsetof(InkPen, tool)};
        break;
      case INK_STRUCT_PDF_EXPORT_SPEC:
        layout = {sizeof(InkPdfExportSpec), offsetof(InkPdfExportSpec, first_page),
                  offsetof(InkPdfExportSpec, page_count), offsetof(InkPdfExportSpec, include_links),
                  offsetof(InkPdfExportSpec, include_hidden_layers)};
        break;
      default:
        return Fail(INK_ERROR_ARGUMENT, "unknown struct");
    }
    if (capacity < layout.size()) return Fail(INK_ERROR_ARGUMENT, "capacity too small");
    for (size_t i = 0; i < layout.size(); ++i) out[i] = uint32_t(layout[i]);
    *count = layout.size();
    return INK_OK;
  });
}

}  // extern "C"
