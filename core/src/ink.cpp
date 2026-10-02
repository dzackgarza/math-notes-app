#include "ink.h"

#include <algorithm>
#include <cmath>
#include <exception>
#include <numbers>
#include <optional>
#include <set>
#include <string>

#include <nlohmann/json.hpp>

#include "editor/canvas.h"
#include "export/pdf.h"
#include "document/templates.h"
#include "document/layers.h"
#include "document/navigation.h"
#include "document/figures.h"
#include "selection/ruled.h"
#include "render/text_layout.h"
#include "render/text_font.h"
#include "format/notebook.h"
#include "format/page_svg.h"
#include "format/pens.h"
#include "geometry/affine.h"
#include "layout/layout.h"
#include "strokes/outline.h"
#include "include/core/SkData.h"
#include "include/core/SkPaint.h"
#include "include/core/SkCanvas.h"
#include "include/core/SkImage.h"
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

// A portrait A4 or Letter keeps its name in notebook.json; every other size
// is stored as its dimensions.
InkStatus ParsePageSize(InkPageSize size, InkOrientation orientation, double width, double height,
                        ink_engine::PageSize *page_size) {
  if (orientation != INK_PORTRAIT && orientation != INK_LANDSCAPE)
    return Fail(INK_ERROR_ARGUMENT, "unknown orientation");
  switch (size) {
    case INK_PAGE_A4: *page_size = std::string("A4"); break;
    case INK_PAGE_LETTER: *page_size = std::string("Letter"); break;
    case INK_PAGE_CUSTOM:
      if (!(width > 0 && height > 0)) return Fail(INK_ERROR_ARGUMENT, "non-positive page size");
      *page_size = std::array<double, 2>{width, height};
      break;
    default: return Fail(INK_ERROR_ARGUMENT, "unknown page size");
  }
  if (orientation == INK_PORTRAIT && std::holds_alternative<std::string>(*page_size)) return INK_OK;
  auto [a, b] = ink_engine::PageDimensions(*page_size);
  auto [shorter, longer] = std::minmax(a, b);
  *page_size = orientation == INK_LANDSCAPE ? std::array<double, 2>{longer, shorter}
                                            : std::array<double, 2>{shorter, longer};
  return INK_OK;
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

uint32_t PackRgb(const ink_engine::Rgb &color) {
  return uint32_t(color.r) << 16 | uint32_t(color.g) << 8 | color.b;
}

ink_engine::Rgb UnpackRgb(uint32_t rgb) { return {uint8_t(rgb >> 16), uint8_t(rgb >> 8), uint8_t(rgb)}; }

ink_engine::Pen ToPen(const InkToolSettings &tool) {
  return {.brush = InkBrush(tool.brush), .color = UnpackRgb(tool.rgb), .size = tool.size, .opacity = tool.opacity};
}

// Each drawing tool has the brush of its name (InkPenFile).
std::optional<std::string> CheckKinds(const InkPenFile &file) {
  if (file.pen.brush != INK_BRUSH_PRESSURE_PEN) return "the pen does not have the pressure-pen brush";
  if (file.marker.brush != INK_BRUSH_MARKER) return "the marker does not have the marker brush";
  if (file.highlighter.brush != INK_BRUSH_HIGHLIGHTER) return "the highlighter does not have the highlighter brush";
  return std::nullopt;
}

// The results of the last ink_pens_* call.
struct PenFile {
  std::string json;
  InkPenFile file;
  std::vector<uint32_t> palette;
  std::vector<InkToolSettings> saved;
  sk_sp<SkData> preview;
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
                                            size_t size, InkPageSize page_size,
                                            InkOrientation orientation, double width,
                                            double height, InkDocument **out) {
  return Call([&] {
    if (!name) return NullArgument("name");
    if (!svg && size) return NullArgument("svg");
    if (!out) return NullArgument("out");
    ink_engine::PageSize parsed_size;
    InkStatus size_status = ParsePageSize(page_size, orientation, width, height, &parsed_size);
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
    if (std::any_of(history.current().pages.begin(), history.current().pages.end(),
                    [](const auto &page) { return ink_engine::HasText(*page); })) {
      for (const auto &[path, bytes] : ink_engine::TextFontFiles()) {
        const auto found = document->assets.find(path);
        if (found != document->assets.end() &&
            std::string_view(static_cast<const char *>(found->second->data()), found->second->size()) != bytes)
          return Fail(INK_ERROR_PARSE, "the bundled text font differs: " + path);
        if (found == document->assets.end()) {
          document->assets[path] = SkData::MakeWithCopy(bytes.data(), bytes.size());
          document->new_assets[path] = bytes;
          ++document->assets_version;
        }
      }
    }
    ink_engine::NotebookFiles changed = ink_engine::ChangedFiles(history.current(), history.saved());
    const std::set<std::string> figure_assets = ink_engine::FigureAssetPaths(history.current());
    const auto saved_assets = history.saved() ? ink_engine::FigureAssetPaths(*history.saved()) : std::set<std::string>{};
    for (const auto &path : figure_assets) {
      if (saved_assets.contains(path)) continue;
      const auto file = document->assets.find(path);
      if (file == document->assets.end()) return Fail(INK_ERROR_PARSE, "missing figure asset: " + path);
      changed[path] = std::string(static_cast<const char *>(file->second->data()), file->second->size());
    }
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

InkStatus ink_document_set_arrangement(InkDocument *document, InkPageArrangement arrangement) {
  return Call([&] {
    if (!document) return NullArgument("document");
    if (arrangement < INK_PAGES_VERTICAL || arrangement > INK_PAGES_TWO_PAGE)
      return Fail(INK_ERROR_ARGUMENT, "unknown page arrangement");
    document->arrangement = ink_engine::PageArrangement(arrangement);
    return INK_OK;
  });
}

InkStatus ink_document_content_size(InkDocument *document, double *width, double *height) {
  return Call([&] {
    if (!document) return NullArgument("document");
    if (!width || !height) return NullArgument("width or height");
    std::vector<ink_engine::PagePlacement> layout =
        ink_engine::LayoutPages(document->history.current(), document->arrangement);
    *width = 0, *height = 0;
    for (const auto &page : layout) {
      *width = std::max(*width, page.x + page.width);
      *height = std::max(*height, page.y + page.height);
    }
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

InkStatus ink_document_layers(InkDocument *document, const char **json) {
  return Call([&] {
    if (!document || !json) return NullArgument("document or json");
    auto values = nlohmann::ordered_json::array();
    for (const auto &layer : document->history.current().notebook.layers)
      values.push_back({{"id", layer.id}, {"name", layer.name}, {"hidden", layer.hidden}, {"locked", layer.locked}});
    document->layers_json = values.dump();
    *json = document->layers_json.c_str();
    return INK_OK;
  });
}

InkStatus ink_document_add_layer(InkDocument *document, const char *name) {
  return Call([&] {
    if (!document || !name) return NullArgument("document or name");
    auto &history = document->history;
    history.Push(ink_engine::AddLayer(history.current(), history.ids(), name));
    return INK_OK;
  });
}

InkStatus ink_document_set_layer(InkDocument *document, size_t index, const char *name, int hidden, int locked) {
  return Call([&] {
    if (!document || !name) return NullArgument("document or name");
    auto &history = document->history;
    history.Push(ink_engine::SetLayer(history.current(), index, name, hidden != 0, locked != 0));
    return INK_OK;
  });
}

InkStatus ink_document_move_layer(InkDocument *document, size_t from, size_t to) {
  return Call([&] {
    if (!document) return NullArgument("document");
    auto &history = document->history;
    history.Push(ink_engine::MoveLayer(history.current(), from, to));
    return INK_OK;
  });
}

InkStatus ink_document_remove_layer(InkDocument *document, size_t index, int merge_down) {
  return Call([&] {
    if (!document) return NullArgument("document");
    auto &history = document->history;
    history.Push(ink_engine::RemoveLayer(history.current(), index, merge_down != 0));
    return INK_OK;
  });
}

InkStatus ink_canvas_set_layer(InkCanvas *canvas, size_t index) {
  return Call([&] {
    if (!canvas) return NullArgument("canvas");
    if (!canvas->editor.SetActiveLayer(index)) return Fail(INK_ERROR_ARGUMENT, "cannot activate this layer during a stroke or drawing capture");
    return INK_OK;
  });
}

InkStatus ink_canvas_active_layer(InkCanvas *canvas, int32_t *index) {
  return Call([&] {
    if (!canvas || !index) return NullArgument("canvas or index");
    *index = canvas->editor.ActiveLayer();
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

InkStatus ink_clipping_add(InkDocument *document, const uint8_t *svg, size_t size) {
  return Call([&] {
    if (!document || !svg) return NullArgument("document or svg");
    auto elements = ink_engine::ReadClipboard(Bytes(svg, size));
    if (!elements || elements->empty()) return Fail(INK_ERROR_PARSE, "clipping has no supported content");
    auto bounds = ink_engine::ElementBounds(**elements->begin());
    for (const auto &element : *elements) bounds = ink_engine::Union(bounds, ink_engine::ElementBounds(*element));
    if (ink_engine::IsEmpty(bounds)) return Fail(INK_ERROR_ARGUMENT, "clipping has no bounds");
    // Write clippingview.cpp:selectionDropped: fit the selection with a small
    // blank margin, then translate its original geometry into that page.
    const double padx = std::max(3.0, (bounds.right - bounds.left) * 0.05);
    const double pady = std::max(3.0, (bounds.bottom - bounds.top) * 0.05);
    auto &history = document->history;
    auto next = history.current();
    auto page = ink_engine::NewPage(next, std::nullopt);
    page.id = history.ids().PageId();
    page.file = ink_engine::NextPageFile(next);
    page.width = bounds.right - bounds.left + 2 * padx;
    page.height = bounds.bottom - bounds.top + 2 * pady;
    if (page.layers.empty()) return Fail(INK_ERROR_ARGUMENT, "clippings need a layer");
    for (const auto &element : *elements) {
      auto copy = ink_engine::Transformed(*element, {.e = padx - bounds.left, .f = pady - bounds.top});
      copy = ink_engine::WithNewIds(copy, history.ids());
      copy = ink_engine::StoreImages(copy, page.file, document->assets, document->new_assets);
      page.layers.front().elements = page.layers.front().elements.push_back(immer::box<ink_engine::Element>(std::move(copy)));
    }
    next.pages = next.pages.insert(ink_engine::ListedPageCount(next), immer::box<ink_engine::Page>(std::move(page)));
    ++document->assets_version;
    history.Push(std::move(next));
    return INK_OK;
  });
}

InkStatus ink_clipping_svg(InkDocument *document, size_t index, const char **svg) {
  return Call([&] {
    if (!document || !svg) return NullArgument("document or svg");
    auto &history = document->history;
    if (index >= ink_engine::ListedPageCount(history.current())) return BadPageIndex();
    const auto &page = *history.current().pages[index];
    if (page.error || page.layers.empty()) return Fail(INK_ERROR_PARSE, "clipping page could not be read");
    ink_engine::Elements elements;
    for (const auto &layer : page.layers) for (const auto &element : layer.elements) {
      auto copy = ink_engine::InlineImages(*element, page.file, document->assets);
      copy = ink_engine::WithoutTimes(ink_engine::WithNewIds(copy, history.ids()));
      elements = elements.push_back(immer::box<ink_engine::Element>(std::move(copy)));
    }
    document->clipping_svg = ink_engine::ClipboardSvg(elements, page.layers.front().layer_id);
    *svg = document->clipping_svg.c_str();
    return INK_OK;
  });
}

namespace {

// Inserts `page` as listed page `index` of `next` with a new page id and new
// element ids, and pushes the result as one history step.
void InsertPageCopy(InkDocument &document, ink_engine::Document next, size_t index,
                    ink_engine::Page page) {
  auto &history = document.history;
  page.id = history.ids().PageId();
  for (auto &layer : page.layers) {
    ink_engine::Elements copied;
    for (const auto &element : layer.elements) {
      auto copy = ink_engine::InlineImages(*element, page.file, document.assets);
      copy = ink_engine::WithNewIds(copy, history.ids());
      copy = ink_engine::StoreImages(copy, page.file, document.assets, document.new_assets);
      copied = copied.push_back(immer::box<ink_engine::Element>(std::move(copy)));
    }
    layer.elements = std::move(copied);
  }
  next.pages = next.pages.insert(index, immer::box<ink_engine::Page>(std::move(page)));
  ++document.assets_version;
  history.Push(std::move(next));
}

}  // namespace

InkStatus ink_import_page_svg(InkDocument *document, size_t index, const uint8_t *svg, size_t size) {
  return Call([&] {
    if (!document || !svg) return NullArgument("document or svg");
    auto next = document->history.current();
    if (index > ink_engine::ListedPageCount(next)) return BadPageIndex();
    std::vector<std::string> layers;
    for (const auto &layer : next.notebook.layers) layers.push_back(layer.id);
    auto page = ink_engine::ReadPage(Bytes(svg, size), ink_engine::NextPageFile(next), layers);
    if (page.error) return Fail(INK_ERROR_PARSE, *page.error);
    InsertPageCopy(*document, std::move(next), index, std::move(page));
    return INK_OK;
  });
}

InkStatus ink_document_duplicate_page(InkDocument *document, size_t index) {
  return Call([&] {
    if (!document) return NullArgument("document");
    auto next = document->history.current();
    if (index >= ink_engine::ListedPageCount(next)) return BadPageIndex();
    ink_engine::Page page = *next.pages[index];
    if (page.error) return Fail(INK_ERROR_ARGUMENT, "a page that did not load cannot be duplicated");
    page.file = ink_engine::NextPageFile(next);
    InsertPageCopy(*document, std::move(next), index + 1, std::move(page));
    return INK_OK;
  });
}

InkStatus ink_import_page_image(InkDocument *document, size_t index, const uint8_t *png,
                                size_t size, double width_pt, double height_pt) {
  return Call([&] {
    if (!document || !png) return NullArgument("document or png");
    if (!std::isfinite(width_pt) || !std::isfinite(height_pt) || width_pt <= 0 || height_pt <= 0)
      return Fail(INK_ERROR_ARGUMENT, "page dimensions must be positive and finite");
    auto bytes = SkData::MakeWithCopy(png, size);
    if (!SkImages::DeferredFromEncodedData(bytes))
      return Fail(INK_ERROR_PARSE, "page image could not be decoded");
    auto &history = document->history;
    if (index > ink_engine::ListedPageCount(history.current())) return BadPageIndex();
    auto next = ink_engine::InsertPage(history.current(), index, history.ids(), std::nullopt);
    auto page = *next.pages[index];
    page.width = width_pt;
    page.height = height_pt;
    size_t number = 1;
    std::string path;
    do {
      auto digits = std::to_string(number++);
      path = "assets/p" + std::string(digits.size() < 4 ? 4 - digits.size() : 0, '0') + digits + ".png";
    } while (document->assets.contains(path));
    page.background.image = ink_engine::Image{
      .id = history.ids().StrokeId(), .href = "../" + path, .width = width_pt, .height = height_pt};
    next.pages = next.pages.set(index, immer::box<ink_engine::Page>(std::move(page)));
    document->assets[path] = std::move(bytes);
    document->new_assets[path] = std::string(Bytes(png, size));
    ++document->assets_version;
    history.Push(std::move(next));
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

InkStatus ink_document_set_page_size(InkDocument *document, InkPageSize size,
                                     InkOrientation orientation, double width, double height) {
  return Call([&] {
    if (!document) return NullArgument("document");
    ink_engine::PageSize page_size;
    InkStatus size_status = ParsePageSize(size, orientation, width, height, &page_size);
    if (size_status != INK_OK) return size_status;
    ink_engine::DocumentHistory &history = document->history;
    if (history.current().notebook.page_size == page_size) return INK_OK;
    history.Push(ink_engine::SetPageSize(history.current(), std::move(page_size)));
    return INK_OK;
  });
}

InkStatus ink_document_page_size(InkDocument *document, InkPageSize *size,
                                 InkOrientation *orientation, double *width, double *height) {
  return Call([&] {
    if (!document) return NullArgument("document");
    if (!size || !orientation || !width || !height) return NullArgument("page size");
    auto [w, h] = ink_engine::PageDimensions(document->history.current().notebook.page_size);
    *width = w, *height = h;
    *orientation = w > h ? INK_LANDSCAPE : INK_PORTRAIT;
    auto [shorter, longer] = std::minmax(w, h);
    std::array<double, 2> portrait{shorter, longer};
    *size = portrait == ink_engine::kA4       ? INK_PAGE_A4
            : portrait == ink_engine::kLetter ? INK_PAGE_LETTER
                                              : INK_PAGE_CUSTOM;
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

InkStatus ink_pens_read(const uint8_t *json, size_t size, const InkPenFile **file) {
  return Call([&] {
    if (!json || !file) return NullArgument("json or file");
    ink_engine::PenFile pens = ink_engine::ReadPens(Bytes(json, size));
    std::optional<std::string> error;
    auto tool = [&](const ink_engine::PenPreset &p) {
      if (ink_engine::BrushName(ink_engine::BrushFromName(p.brush)) != p.brush) error = "unknown brush " + p.brush;
      InkToolSettings settings{.brush = uint32_t(ink_engine::BrushFromName(p.brush)),
                               .rgb = PackRgb(p.color),
                               .size = float(p.size),
                               .opacity = float(p.opacity)};
      if (auto bad = CheckTool(settings)) error = *bad;
      return settings;
    };
    gPenFile.palette.clear();
    for (const ink_engine::Rgb &color : pens.palette) gPenFile.palette.push_back(PackRgb(color));
    gPenFile.saved.clear();
    for (const ink_engine::PenPreset &p : pens.saved) gPenFile.saved.push_back(tool(p));
    gPenFile.file = {.pen = tool(pens.pen),
                     .marker = tool(pens.marker),
                     .highlighter = tool(pens.highlighter),
                     .palette = gPenFile.palette.data(),
                     .palette_count = gPenFile.palette.size(),
                     .saved = gPenFile.saved.data(),
                     .saved_count = gPenFile.saved.size()};
    if (!error) error = CheckKinds(gPenFile.file);
    if (error) return Fail(INK_ERROR_PARSE, *error);
    *file = &gPenFile.file;
    return INK_OK;
  });
}

InkStatus ink_pens_write(const InkPenFile *file, const uint8_t **json, size_t *size) {
  return Call([&] {
    if (!file || (!file->palette && file->palette_count) || (!file->saved && file->saved_count) || !json ||
        !size)
      return NullArgument("file, palette, saved, json or size");
    std::optional<std::string> error = CheckKinds(*file);
    auto preset = [&](const InkToolSettings &tool) {
      if (auto bad = CheckTool(tool)) error = *bad;
      ink_engine::Pen pen = ToPen(tool);
      return ink_engine::PenPreset{.brush = ink_engine::BrushName(pen.brush), .color = pen.color,
                                   .opacity = pen.opacity, .size = pen.size};
    };
    ink_engine::PenFile pens{
        .pen = preset(file->pen), .marker = preset(file->marker), .highlighter = preset(file->highlighter)};
    for (size_t i = 0; i < file->palette_count; ++i) pens.palette.push_back(UnpackRgb(file->palette[i]));
    for (size_t i = 0; i < file->saved_count; ++i) pens.saved.push_back(preset(file->saved[i]));
    if (error) return Fail(INK_ERROR_ARGUMENT, *error);
    gPenFile.json = ink_engine::WritePens(pens);
    *json = reinterpret_cast<const uint8_t *>(gPenFile.json.data());
    *size = gPenFile.json.size();
    return INK_OK;
  });
}

InkStatus ink_pens_preview_png(const InkToolSettings *tool, int32_t width, int32_t height,
                               float scale, const uint8_t **png, size_t *size) {
  return Call([&] {
    if (!tool || !png || !size) return NullArgument("tool, png or size");
    if (auto error = CheckTool(*tool)) return Fail(INK_ERROR_ARGUMENT, *error);
    if (width <= 0 || width > 4096 || height <= 0 || height > 4096 || !(scale > 0)) {
      return Fail(INK_ERROR_ARGUMENT, "invalid preview size");
    }
    // One wave across the middle 70% of the image, drawn with a stylus whose
    // pressure rises and falls, so the brush's width response shows.
    const float w = width / scale, h = height / scale;
    constexpr int kSamples = 64;
    ink::StrokeInputBatch batch;
    for (int i = 0; i <= kSamples; ++i) {
      const float t = float(i) / kSamples;
      const float phase = 2 * std::numbers::pi_v<float> * t;
      (void)batch.Append({.tool_type = ink::StrokeInput::ToolType::kStylus,
                          .position = {w * (0.15f + 0.7f * t), h / 2 - h / 4 * std::sin(phase)},
                          .elapsed_time = ink::Duration32::Millis(8.0f * i),
                          .pressure = 0.3f + 0.6f * std::sin(std::numbers::pi_v<float> * t)});
    }
    const ink_engine::Pen pen = ToPen(*tool);
    const ink::Stroke stroke(ink_engine::MakeBrush(pen), batch);
    auto surface = SkSurfaces::Raster(SkImageInfo::MakeN32Premul(width, height));
    if (!surface) return Fail(INK_ERROR_INTERNAL, "cannot allocate pen preview");
    surface->getCanvas()->scale(scale, scale);
    SkPaint paint(SkColor4f::FromColor(SkColorSetARGB(uint8_t(std::lround(pen.opacity * 255)),
                                                      pen.color.r, pen.color.g, pen.color.b)));
    paint.setAntiAlias(true);
    surface->getCanvas()->drawPath(
        ink_engine::OutlinePath(ink_engine::StrokeOutline(stroke.GetShape())), paint);
    SkPixmap pixels;
    if (!surface->peekPixels(&pixels)) return Fail(INK_ERROR_INTERNAL, "no preview pixels");
    SkDynamicMemoryWStream out;
    if (!SkPngEncoder::Encode(&out, pixels, {})) return Fail(INK_ERROR_INTERNAL, "PNG encoding failed");
    gPenFile.preview = out.detachAsData();
    *png = gPenFile.preview->bytes();
    *size = gPenFile.preview->size();
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
    if (kind < INK_SELECTOR_LASSO || kind > INK_SELECTOR_OVAL) {
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
        ink_engine::LayoutPages(canvas->document->history.current(), canvas->document->arrangement);
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

InkStatus ink_canvas_bookmark_selection(InkCanvas *canvas) {
  return Call([&] {
    if (!canvas) return NullArgument("canvas");
    canvas->editor.BookmarkSelection();
    return INK_OK;
  });
}

InkStatus ink_document_figure_source(InkDocument *document, const char *id, const uint8_t **text, size_t *size) {
  return Call([&] {
    if (!document || !id || !text || !size) return NullArgument("figure source argument");
    const auto &current = document->history.current();
    const auto location = ink_engine::FindFigure(current, id);
    const auto &href = location.figure->draft_href.empty() ? location.figure->tikz_href : location.figure->draft_href;
    const auto path = ink_engine::NotebookPath(current.pages[location.page]->file, href);
    const auto file = document->assets.find(path);
    if (file == document->assets.end()) return Fail(INK_ERROR_PARSE, "missing figure source: " + path);
    document->figure_source.assign(static_cast<const char *>(file->second->data()), file->second->size());
    *text = reinterpret_cast<const uint8_t *>(document->figure_source.data());
    *size = document->figure_source.size();
    return INK_OK;
  });
}

InkStatus ink_document_figure_draft(InkDocument *document, const char *id, const uint8_t *text, size_t size) {
  return Call([&] {
    if (!document || !id || (!text && size)) return NullArgument("figure draft argument");
    auto &history = document->history;
    const auto location = ink_engine::FindFigure(history.current(), id);
    const auto &href = location.figure->draft_href.empty() ? location.figure->tikz_href : location.figure->draft_href;
    const auto previous = document->assets.find(ink_engine::NotebookPath(history.current().pages[location.page]->file, href));
    if (previous != document->assets.end() && std::string_view(static_cast<const char *>(previous->second->data()), previous->second->size()) == Bytes(text, size)) return INK_OK;
    const std::string path = std::string("assets/") + id + "-" + history.ids().StrokeId() + ".draft.tikz";
    auto next = ink_engine::SetFigureDraft(history.current(), id, "../" + path);
    document->assets[path] = SkData::MakeWithCopy(text, size);
    document->new_assets[path] = std::string(Bytes(text, size));
    ++document->assets_version;
    history.Push(std::move(next));
    return INK_OK;
  });
}

InkStatus ink_canvas_link_selection(InkCanvas *canvas, const char *href) {
  return Call([&] {
    if (!canvas || !href) return NullArgument("canvas or href");
    canvas->editor.LinkSelection(href);
    return INK_OK;
  });
}
InkStatus ink_canvas_ungroup_selection(InkCanvas *canvas) {
  return Call([&] {
    if (!canvas) return NullArgument("canvas");
    canvas->editor.UngroupSelection();
    return INK_OK;
  });
}
InkStatus ink_canvas_add_bookmark(InkCanvas *canvas, double x, double y) {
  return Call([&] {
    if (!canvas) return NullArgument("canvas");
    canvas->editor.AddBookmark(x, y);
    return INK_OK;
  });
}
InkStatus ink_document_navigation(InkDocument *document, const char **json) {
  return Call([&] {
    if (!document || !json) return NullArgument("document or json");
    const auto &current = document->history.current();
    auto value = nlohmann::json::array();
    for (size_t p = 0; p < ink_engine::ListedPageCount(current); ++p)
      value.push_back({{"id", ""}, {"href", ""}, {"page", p}, {"file", current.pages[p]->file},
                       {"x", 0}, {"y", 0}, {"width", current.pages[p]->width}, {"height", 0}});
    for (const auto &mark : ink_engine::NavigationMarks(current))
      value.push_back({{"id", mark.id}, {"href", mark.href}, {"page", mark.page},
                       {"file", current.pages[mark.page]->file},
                       {"x", mark.bounds.left}, {"y", mark.bounds.top},
                       {"width", mark.bounds.right - mark.bounds.left},
                       {"height", mark.bounds.bottom - mark.bounds.top}});
    document->navigation_json = value.dump();
    *json = document->navigation_json.c_str();
    return INK_OK;
  });
}

InkStatus ink_document_bookmark_png(InkDocument *document, const char *id, int32_t width,
                                    const uint8_t **png, size_t *size) {
  return Call([&] {
    if (!document || !id || !png || !size) return NullArgument("bookmark PNG argument");
    if (width <= 0 || width > 4096) return Fail(INK_ERROR_ARGUMENT, "invalid preview width");
    const auto &current = document->history.current();
    const auto marks = ink_engine::NavigationMarks(current);
    const auto mark = std::find_if(marks.begin(), marks.end(), [&](const auto &m) { return m.id == id; });
    if (mark == marks.end()) return Fail(INK_ERROR_ARGUMENT, "bookmark no longer exists");
    const auto page = ink_engine::BookmarkLine(*current.pages[mark->page], mark->bounds);
    const auto grid = ink_engine::WorkingGrid(page, (mark->bounds.top + mark->bounds.bottom) / 2);
    const double top = std::max(0.0, grid.Top(grid.Line((mark->bounds.top + mark->bounds.bottom) / 2)) - grid.spacing / 4);
    const double scale = width / page.width;
    const int height = std::max(1, int(std::ceil(grid.spacing * 1.5 * scale)));
    auto surface = SkSurfaces::Raster(SkImageInfo::MakeN32Premul(width, height));
    if (!surface) return Fail(INK_ERROR_INTERNAL, "cannot allocate bookmark preview");
    surface->getCanvas()->scale(scale, scale);
    surface->getCanvas()->translate(0, -top);
    ink_engine::Renderer renderer(nullptr, document->assets);
    renderer.DrawPageForExport(surface->getCanvas(), current, page, false);
    SkPixmap pixels;
    if (!surface->peekPixels(&pixels)) return Fail(INK_ERROR_INTERNAL, "no preview pixels");
    SkDynamicMemoryWStream out;
    if (!SkPngEncoder::Encode(&out, pixels, {})) return Fail(INK_ERROR_INTERNAL, "PNG encoding failed");
    document->png.resize(out.bytesWritten());
    out.copyTo(document->png.data());
    *png = reinterpret_cast<const uint8_t *>(document->png.data());
    *size = document->png.size();
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

static InkStatus PasteCanvas(InkCanvas *canvas, const uint8_t *svg, size_t size, double x,
                           double y, bool place_at_pointer) {
  return Call([&] {
    if (!canvas) return NullArgument("canvas");
    if (!svg && size) return NullArgument("svg");
    InkDocument &document = *canvas->document;
    ink_engine::NotebookFiles added;
    if (!canvas->editor.Paste(Bytes(svg, size), x, y, canvas->width / canvas->pixel_ratio,
                              canvas->height / canvas->pixel_ratio, document.assets, added, place_at_pointer)) {
      return Fail(INK_ERROR_PARSE, "the clipboard text is not a page SVG");
    }
    if (!added.empty()) {
      document.new_assets.insert(added.begin(), added.end());
      ++document.assets_version;
    }
    return INK_OK;
  });
}

InkStatus ink_canvas_paste(InkCanvas *canvas, const uint8_t *svg, size_t size, double x, double y) {
  return PasteCanvas(canvas, svg, size, x, y, false);
}

InkStatus ink_canvas_paste_at(InkCanvas *canvas, const uint8_t *svg, size_t size, double x, double y) {
  return PasteCanvas(canvas, svg, size, x, y, true);
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

InkStatus ink_canvas_recolor_selection(InkCanvas *canvas, uint32_t rgb) {
  return Call([&] {
    if (!canvas) return NullArgument("canvas");
    if (rgb > 0xFFFFFF) return Fail(INK_ERROR_ARGUMENT, "the color must be 0xRRGGBB");
    canvas->editor.RecolorSelection({uint8_t(rgb >> 16), uint8_t(rgb >> 8), uint8_t(rgb)});
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

InkStatus ink_canvas_text_properties(InkCanvas *canvas, const char **json) {
  return Call([&] {
    if (!canvas || !json) return NullArgument("canvas or json");
    const auto *text = canvas->editor.SelectedTextValue();
    if (!text) return Fail(INK_ERROR_ARGUMENT, "select a text box");
    canvas->selected_text = nlohmann::json({{"content", *canvas->editor.SelectedText()},
                                           {"width", text->width}, {"rtl", text->rtl}}).dump();
    *json = canvas->selected_text.c_str();
    return INK_OK;
  });
}

InkStatus ink_canvas_edit_text(InkCanvas *canvas, const char *json, double x, double y, int32_t existing) {
  return Call([&] {
    if (!canvas || !json) return NullArgument("canvas or json");
    const auto value = nlohmann::json::parse(json);
    const auto content = value.at("content").get<std::string>();
    const ink_engine::TextBoxStyle style{value.at("width").get<double>(), value.at("rtl").get<bool>()};
    if (!std::isfinite(style.width) || style.width < 0 || style.width > 100000)
      return Fail(INK_ERROR_ARGUMENT, "invalid text box width");
    const bool changed = existing ? canvas->editor.SetSelectedText(content, style)
                                 : canvas->editor.InsertText(content, x, y, style);
    if (!changed) return Fail(INK_ERROR_ARGUMENT, "select an editable text box or page");
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
        ink_engine::LayoutPages(canvas->document->history.current(), canvas->document->arrangement);
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
    if (count && std::any_of(samples, samples + count, [](const InkPenSample &sample) { return sample.phase == INK_PHASE_BEGIN; }))
      canvas->editor.SetTemplate(canvas->document->template_page);
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
    ink_engine::View view{editor.view(), canvas->pixel_ratio, canvas->width, canvas->height,
                          canvas->document->arrangement};
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

InkStatus ink_canvas_invalidate(InkCanvas *canvas) {
  return Call([&] {
    if (!canvas) return NullArgument("canvas");
    canvas->renderer->Invalidate();
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
        ink_engine::LayoutPages(document->history.current(), document->arrangement);
    if (index >= layout.size()) return BadPageIndex();
    const ink_engine::PagePlacement &p = layout[index];
    *x = p.x, *y = p.y, *width = p.width, *height = p.height;
    return INK_OK;
  });
}

static InkStatus RenderPagePng(InkDocument *document, size_t index,
                               std::optional<size_t> layer, int32_t width,
                               const uint8_t **png, size_t *size) {
  return Call([&] {
    if (!document) return NullArgument("document");
    if (!png || !size) return NullArgument("png or size");
    if (width <= 0) return Fail(INK_ERROR_ARGUMENT, "non-positive width");
    const ink_engine::Document &source = document->history.current();
    if (layer && *layer >= source.notebook.layers.size())
      return Fail(INK_ERROR_ARGUMENT, "layer index out of range");
    std::optional<ink_engine::Document> filtered;
    if (layer) {
      filtered.emplace(source);
      for (size_t i = 0; i < filtered->notebook.layers.size(); ++i)
        filtered->notebook.layers[i].hidden = i != *layer;
    }
    const ink_engine::Document &current = filtered ? *filtered : source;
    std::vector<ink_engine::PagePlacement> layout = ink_engine::LayoutPages(current, document->arrangement);
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

InkStatus ink_document_page_png(InkDocument *document, size_t index, int32_t width,
                                const uint8_t **png, size_t *size) {
  return RenderPagePng(document, index, std::nullopt, width, png, size);
}

InkStatus ink_document_layer_png(InkDocument *document, size_t page, size_t layer,
                                 int32_t width, const uint8_t **png, size_t *size) {
  return RenderPagePng(document, page, layer, width, png, size);
}

static InkStatus ExportPdfSelection(InkDocument *document, const char *title,
                         const InkPdfExportSpec *spec, const char *layers, const uint8_t **pdf, size_t *size) {
  return Call([&] {
    if (!document) return NullArgument("document");
    if (!title) return NullArgument("title");
    if (!spec || !pdf || !size) return NullArgument("spec, pdf or size");
    if (!*title) return Fail(INK_ERROR_ARGUMENT, "empty PDF title");
    auto current = document->history.current();
    if (layers) {
      const auto ids = nlohmann::json::parse(layers).get<std::set<std::string>>();
      for (auto &layer : current.notebook.layers) layer.hidden = !ids.contains(layer.id);
    }
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
                               spec->page_count, !layers && spec->include_hidden_layers != 0,
                               &document->pdf, spec->include_links != 0)) {
      return Fail(INK_ERROR_INTERNAL, "PDF export failed");
    }
    *pdf = reinterpret_cast<const uint8_t *>(document->pdf.data());
    *size = document->pdf.size();
    return INK_OK;
  });
}

InkStatus ink_export_pdf(InkDocument *document, const char *title,
                         const InkPdfExportSpec *spec, const uint8_t **pdf, size_t *size) {
  return ExportPdfSelection(document, title, spec, nullptr, pdf, size);
}

InkStatus ink_export_pdf_layers(InkDocument *document, const char *title,
                         const InkPdfExportSpec *spec, const char *layers, const uint8_t **pdf, size_t *size) {
  if (!layers) return NullArgument("layers");
  return ExportPdfSelection(document, title, spec, layers, pdf, size);
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
      case INK_STRUCT_PEN_FILE:
        layout = {sizeof(InkPenFile),
                  offsetof(InkPenFile, pen),
                  offsetof(InkPenFile, marker),
                  offsetof(InkPenFile, highlighter),
                  offsetof(InkPenFile, palette),
                  offsetof(InkPenFile, palette_count),
                  offsetof(InkPenFile, saved),
                  offsetof(InkPenFile, saved_count)};
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
