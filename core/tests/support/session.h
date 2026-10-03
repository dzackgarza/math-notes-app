// A document and one canvas on it without a GPU surface: the engine's input
// path through the C ABI, for tests that do not render.
#pragma once

#include <memory>

#include "editor/canvas.h"
#include "ink.h"

namespace ink_test {

struct Session {
  explicit Session(uint64_t seed = 1) {
    ink_document_create(seed, &document);
    canvas = std::make_unique<InkCanvas>(*document);
  }
  explicit Session(ink_engine::Document loaded, uint64_t seed = 1) : Session(seed) {
    document->history.Reset(std::move(loaded));
    canvas = std::make_unique<InkCanvas>(*document);
  }
  ~Session() {
    canvas.reset();
    ink_document_free(document);
  }
  Session(const Session &) = delete;
  Session &operator=(const Session &) = delete;

  InkCanvas *get() const { return canvas.get(); }
  const ink_engine::Document &doc() const { return document->history.current(); }

  InkDocument *document = nullptr;
  std::unique_ptr<InkCanvas> canvas;
};

inline void SetTool(InkCanvas *canvas, InkBrush brush, uint32_t rgb, float size,
                    float opacity = 1) {
  InkToolSettings tool{uint32_t(brush), rgb, size, opacity, 0, 20};
  ink_canvas_set_tool(canvas, &tool);
}

}  // namespace ink_test
