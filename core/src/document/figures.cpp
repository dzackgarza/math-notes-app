#include "document/figures.h"

#include <algorithm>
#include <stdexcept>

namespace ink_engine {
namespace {
const Figure *Find(const Elements &elements, const std::string &id) {
  for (const auto &box : elements) {
    const Figure *found = std::visit(
        [&](const auto &value) -> const Figure * {
          using T = std::decay_t<decltype(value)>;
          if constexpr (std::is_same_v<T, Figure>)
            if (value.id == id) return &value;
          if constexpr (std::is_same_v<T, Figure> || std::is_same_v<T, Bookmark> ||
                        std::is_same_v<T, Link>)
            return Find(value.children, id);
          return nullptr;
        },
        box->value);
    if (found) return found;
  }
  return nullptr;
}

Elements SetDraft(Elements elements, const std::string &id, const std::string &href) {
  for (size_t i = 0; i < elements.size(); ++i) {
    Element changed = *elements[i];
    std::visit(
        [&](auto &value) {
          using T = std::decay_t<decltype(value)>;
          if constexpr (std::is_same_v<T, Figure>)
            if (value.id == id) {
              value.draft_href = href;
              return;
            }
          if constexpr (std::is_same_v<T, Figure> || std::is_same_v<T, Bookmark> ||
                        std::is_same_v<T, Link>)
            value.children = SetDraft(value.children, id, href);
        },
        changed.value);
    if (changed != *elements[i])
      elements = elements.set(i, immer::box<Element>(std::move(changed)));
  }
  return elements;
}
}  // namespace

FigureLocation FindFigure(const Document &document, const std::string &id) {
  for (size_t p = 0; p < document.pages.size(); ++p)
    for (size_t l = 0; l < document.pages[p]->layers.size(); ++l)
      if (const auto *figure = Find(document.pages[p]->layers[l].elements, id))
        return {figure, p, l};
  throw std::invalid_argument("figure no longer exists");
}

Document SetFigureDraft(Document document, const std::string &id, const std::string &href) {
  const auto location = FindFigure(document, id);
  Page page = *document.pages[location.page];
  const auto &layer_id = page.layers[location.layer].layer_id;
  const auto layer = std::find_if(document.notebook.layers.begin(), document.notebook.layers.end(),
                                  [&](const Layer &l) { return l.id == layer_id; });
  if (page.error || (layer != document.notebook.layers.end() && (layer->hidden || layer->locked)))
    throw std::invalid_argument("choose a figure on an editable layer");
  page.layers[location.layer].elements = SetDraft(page.layers[location.layer].elements, id, href);
  document.pages = document.pages.set(location.page, immer::box<Page>(std::move(page)));
  return document;
}
}  // namespace ink_engine
