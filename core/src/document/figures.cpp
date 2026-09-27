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

Elements Replace(Elements elements, const Figure &figure) {
  for (size_t i = 0; i < elements.size(); ++i) {
    Element changed = *elements[i];
    std::visit(
        [&](auto &value) {
          using T = std::decay_t<decltype(value)>;
          if constexpr (std::is_same_v<T, Figure>)
            if (value.id == figure.id) {
              value = figure;
              return;
            }
          if constexpr (std::is_same_v<T, Figure> || std::is_same_v<T, Bookmark> ||
                        std::is_same_v<T, Link>)
            value.children = Replace(value.children, figure);
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
  Figure figure = *FindFigure(document, id).figure;
  figure.draft_href = href;
  return ReplaceFigure(std::move(document), figure);
}

Document ReplaceFigure(Document document, const Figure &figure) {
  const auto location = FindFigure(document, figure.id);
  Page page = *document.pages[location.page];
  const auto &layer_id = page.layers[location.layer].layer_id;
  const auto layer = std::find_if(document.notebook.layers.begin(), document.notebook.layers.end(),
                                  [&](const Layer &l) { return l.id == layer_id; });
  if (page.error || (layer != document.notebook.layers.end() && (layer->hidden || layer->locked)))
    throw std::invalid_argument("choose a figure on an editable layer");
  page.layers[location.layer].elements = Replace(page.layers[location.layer].elements, figure);
  document.pages = document.pages.set(location.page, immer::box<Page>(std::move(page)));
  return document;
}
}  // namespace ink_engine
