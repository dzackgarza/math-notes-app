#include "document/pages.h"

#include <stdexcept>

#include "document/templates.h"
#include "format/notebook.h"

namespace ink_engine {

std::array<double, 2> PageDimensions(const PageSize &size) {
  if (auto *dims = std::get_if<std::array<double, 2>>(&size)) return *dims;
  return std::get<std::string>(size) == "Letter" ? kLetter : kA4;
}

Document NewNotebook(IdGenerator &ids, PageSize size, const std::optional<Page> &template_page) {
  Document document;
  document.notebook.page_size = std::move(size);
  document.notebook.template_name = "blank";
  document.notebook.layers.push_back({.id = ids.LayerId(), .name = "Ink"});
  Page page = NewPage(document, template_page);
  page.id = ids.PageId();
  page.file = "pages/0001.svg";
  document.pages = document.pages.push_back(immer::box<Page>(std::move(page)));
  return document;
}

size_t ListedPageCount(const Document &document) {
  size_t count = 0;
  while (count < document.pages.size() && !document.pages[count]->unlisted) ++count;
  return count;
}

namespace {

void RequireIndex(size_t index, size_t limit) {
  if (index >= limit) throw std::out_of_range("page index out of range");
}

}  // namespace

Page NewPage(const Document &document, const std::optional<Page> &template_page) {
  auto [width, height] = PageDimensions(document.notebook.page_size);
  Page page{.width = width, .height = height};
  if (!template_page) {
    page.background = MakeBackground({Ruling::kBlank}, width, height);
  } else if (template_page->width == width && template_page->height == height) {
    page.background = template_page->background;
  } else {
    const Background &t = template_page->background;
    page.background = MakeBackground({t.ruling, t.y_ruling, t.x_ruling, t.margin_left}, width, height);
    page.background.fill = t.fill;
  }
  for (const Layer &layer : document.notebook.layers) page.layers.push_back({.layer_id = layer.id});
  return page;
}

Document InsertPage(Document document, size_t index, IdGenerator &ids,
                    const std::optional<Page> &template_page) {
  RequireIndex(index, ListedPageCount(document) + 1);
  Page page = NewPage(document, template_page);
  page.id = ids.PageId();
  page.file = NextPageFile(document);
  document.pages = document.pages.insert(index, immer::box<Page>(std::move(page)));
  return document;
}

Document DeletePage(Document document, size_t index) {
  RequireIndex(index, ListedPageCount(document));
  document.pages = document.pages.erase(index);
  return document;
}

Document MovePage(Document document, size_t from, size_t to) {
  size_t count = ListedPageCount(document);
  RequireIndex(from, count);
  RequireIndex(to, count);
  immer::box<Page> page = document.pages[from];
  document.pages = document.pages.erase(from).insert(to, page);
  return document;
}

Document SetPageSize(Document document, PageSize size) {
  document.notebook.page_size = std::move(size);
  return document;
}

}  // namespace ink_engine

namespace ink_engine {

std::optional<size_t> FirstChangedPage(const Document &before, const Document &after) {
  size_t a = ListedPageCount(before), b = ListedPageCount(after);
  for (size_t i = 0; i < std::min(a, b); ++i) {
    if (&*before.pages[i] != &*after.pages[i]) return i;
  }
  if (a == b || b == 0) return std::nullopt;
  return std::min(a, b) == b ? b - 1 : a;
}

}  // namespace ink_engine
