#include "document/navigation.h"

#include <algorithm>
#include <filesystem>

#include "selection/ruled.h"

namespace ink_engine {
namespace {
void Collect(const Elements &elements, size_t page, std::vector<NavigationMark> &marks) {
  for (const auto &box : elements) {
    const auto bounds = ElementBounds(*box);
    if (const auto *bookmark = std::get_if<Bookmark>(&box->value)) {
      marks.push_back({bookmark->id, {}, page, bounds});
      Collect(bookmark->children, page, marks);
    } else if (const auto *link = std::get_if<Link>(&box->value)) {
      marks.push_back({{}, link->href, page, bounds});
      Collect(link->children, page, marks);
    } else if (const auto *figure = std::get_if<Figure>(&box->value)) {
      Elements children;
      for (const auto &child : figure->children)
        children = children.push_back(immer::box<Element>(Transformed(*child, figure->transform)));
      Collect(children, page, marks);
    }
  }
}
}  // namespace

std::vector<NavigationMark> NavigationMarks(const Document &document, bool include_hidden) {
  std::vector<NavigationMark> marks;
  for (size_t p = 0; p < document.pages.size(); ++p) {
    if (document.pages[p]->unlisted || document.pages[p]->error) continue;
    for (const auto &layer : document.pages[p]->layers) {
      const auto meta =
          std::find_if(document.notebook.layers.begin(), document.notebook.layers.end(),
                       [&](const Layer &value) { return value.id == layer.layer_id; });
      if (!include_hidden && meta != document.notebook.layers.end() && meta->hidden) continue;
      Collect(layer.elements, p, marks);
    }
  }
  std::stable_sort(marks.begin(), marks.end(), [](const auto &a, const auto &b) {
    return std::tie(a.page, a.bounds.top, a.bounds.left) <
           std::tie(b.page, b.bounds.top, b.bounds.left);
  });
  return marks;
}

Page BookmarkLine(const Page &source, const Rect &bookmark) {
  Page page = source;
  const double y = (bookmark.top + bookmark.bottom) / 2;
  const auto range = MakeRuledRange(page, {bookmark.left, y}, {page.width, y});
  for (auto &layer : page.layers) {
    Elements selected;
    for (const auto &element : layer.elements)
      if (InRuledRange(*element, range)) selected = selected.push_back(element);
    layer.elements = std::move(selected);
  }
  return page;
}

std::string PageLinkTarget(const Page &source, const std::string &href) {
  if (href.find(':') != std::string::npos || href.starts_with('/')) return href;
  const auto hash = href.find('#');
  const auto path = href.substr(0, hash);
  return (path.empty() ? source.file
                       : (std::filesystem::path(source.file).parent_path() / path)
                             .lexically_normal()
                             .generic_string()) +
         (hash == std::string::npos ? "" : href.substr(hash));
}
}  // namespace ink_engine
