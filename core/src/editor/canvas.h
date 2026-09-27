// The objects behind the C ABI's opaque handles.
#pragma once

#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "document/pages.h"
#include "editor/editor.h"
#include "editor/history.h"
#include "render/host_surface.h"
#include "render/renderer.h"

struct InkDocument {
  ink_engine::DocumentHistory history;
  ink_engine::Assets assets;
  uint64_t assets_version = 0;  // counts changes to `assets`
  // Image files a paste added, which the next ink_document_dirty_files lists.
  ink_engine::NotebookFiles new_assets;
  // Page 1 of the notebook's template notebook (ink_document_set_template).
  std::optional<ink_engine::Page> template_page;
  // The last ink_document_dirty_files result, which the host reads in place.
  std::vector<std::pair<std::string, std::string>> dirty;
  std::vector<std::string> dirty_removed;
  std::vector<InkFile> dirty_view;
  // The last ink_document_page_png result.
  std::string png;
  // The last ink_export_pdf result.
  std::string pdf;
};

struct InkCanvas {
  explicit InkCanvas(InkDocument &doc) : document(&doc), editor(doc.history) {}

  InkDocument *document;
  ink_engine::Editor editor;
  std::unique_ptr<ink_engine::HostSurface> surface;
  std::unique_ptr<ink_engine::Renderer> renderer;
  int width = 0, height = 0;  // device pixels
  float pixel_ratio = 1;
  bool was_drawing = false;
  std::string clipboard;  // the last ink_canvas_copy_selection result
  std::string selected_text;  // the last ink_canvas_selected_text result
  std::string figure_scene;   // the last ink_canvas_figure_scene result
  std::string figure_id;      // the last ink_canvas_figure_complete result
  uint64_t assets_seen = 0;
};
