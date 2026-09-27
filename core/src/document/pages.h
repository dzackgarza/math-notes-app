// Page operations on a document value (docs/FORMAT.md, notebook.json and
// Page files). Each returns the next value; the editor pushes it as one
// history step. Indices count listed pages, in notebook.json order.
#pragma once

#include <array>
#include <cstddef>
#include <optional>

#include "document/document.h"
#include "document/ids.h"

namespace ink_engine {

inline constexpr std::array<double, 2> kA4 = {595.28, 841.89};
inline constexpr std::array<double, 2> kLetter = {612, 792};

// Width and height in pt of "A4", "Letter" or [width, height].
std::array<double, 2> PageDimensions(const PageSize &size);

// A new notebook: one layer and one page at the selected size and background.
Document NewNotebook(IdGenerator &ids, PageSize size = std::string("A4"),
                     const std::optional<Page> &template_page = std::nullopt);

size_t ListedPageCount(const Document &document);

// A new page before listed page `index` (the count appends), in the
// notebook's page size, with the template's background: copied when the
// template page has the same size, generated from its ruling otherwise
// (Write syncscribble/scribbledoc.cpp:362-379: a new page copies the
// reference page's ruling). Its file is the next unused number.
Document InsertPage(Document document, size_t index, IdGenerator &ids,
                    const std::optional<Page> &template_page);

// A page for the notebook's page size and template, before it gets an id
// and a file.
Page NewPage(const Document &document, const std::optional<Page> &template_page);

// Removes listed page `index`; the host deletes its file on save.
Document DeletePage(Document document, size_t index);

// Moves listed page `from` to position `to`; files keep their names.
Document MovePage(Document document, size_t from, size_t to);

// The size of new pages.
Document SetPageSize(Document document, PageSize size);

}  // namespace ink_engine

namespace ink_engine {

// The first listed page of `after` whose value is not the one in `before`:
// the page an undo or redo shows (Write syncscribble/syncundo.cpp:238-303
// shows the page of the undone action). The last page when only pages
// after it were removed; none when only notebook settings changed.
std::optional<size_t> FirstChangedPage(const Document &before, const Document &after);

}  // namespace ink_engine
