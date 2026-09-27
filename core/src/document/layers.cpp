// Notebook-wide counterparts of Xournal++ LayerController.cpp operations:
// insert (177), remove (198), move (227), merge down (274), rename (437).
#include "document/layers.h"
#include <stdexcept>

namespace ink_engine {
namespace {
void Check(const Document &document, size_t index) {
  if (index >= document.notebook.layers.size()) throw std::out_of_range("layer index out of range");
  for (const auto &page : document.pages) {
    if (page->error) throw std::runtime_error("repair error pages before changing layers");
  }
}
void RequireName(const std::string &name) {
  if (name.empty()) throw std::invalid_argument("layer name is empty");
}
}  // namespace

Document AddLayer(Document document, IdGenerator &ids, std::string name) {
  RequireName(name);
  Check(document, 0);
  const auto at = document.notebook.layers.size();
  const std::string id = ids.LayerId();
  document.notebook.layers.push_back({.id = id, .name = std::move(name)});
  for (size_t i = 0; i < document.pages.size(); ++i) {
    auto page = *document.pages[i];
    page.layers.insert(page.layers.begin() + at, LayerContent{.layer_id = id});
    document.pages = document.pages.set(i, immer::box<Page>(std::move(page)));
  }
  return document;
}

Document SetLayer(Document document, size_t index, std::string name, bool hidden, bool locked) {
  Check(document, index);
  RequireName(name);
  auto &layer = document.notebook.layers[index];
  layer.name = std::move(name);
  layer.hidden = hidden;
  layer.locked = locked;
  return document;
}

Document MoveLayer(Document document, size_t from, size_t to) {
  Check(document, from);
  Check(document, to);
  auto layer = document.notebook.layers[from];
  document.notebook.layers.erase(document.notebook.layers.begin() + from);
  document.notebook.layers.insert(document.notebook.layers.begin() + to, std::move(layer));
  for (size_t i = 0; i < document.pages.size(); ++i) {
    auto page = *document.pages[i];
    auto content = page.layers[from];
    page.layers.erase(page.layers.begin() + from);
    page.layers.insert(page.layers.begin() + to, std::move(content));
    document.pages = document.pages.set(i, immer::box<Page>(std::move(page)));
  }
  return document;
}

Document RemoveLayer(Document document, size_t index, bool merge_down) {
  Check(document, index);
  if (document.notebook.layers.size() == 1) throw std::invalid_argument("keep at least one layer");
  if (merge_down && (index == 0 || document.notebook.layers[index - 1].locked))
    throw std::invalid_argument("no unlocked layer below this layer");
  document.notebook.layers.erase(document.notebook.layers.begin() + index);
  for (size_t i = 0; i < document.pages.size(); ++i) {
    auto page = *document.pages[i];
    if (merge_down) page.layers[index - 1].elements = page.layers[index - 1].elements + page.layers[index].elements;
    page.layers.erase(page.layers.begin() + index);
    document.pages = document.pages.set(i, immer::box<Page>(std::move(page)));
  }
  return document;
}
}  // namespace ink_engine
