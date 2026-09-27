#pragma once

#include <cstddef>
#include <string>

#include "document/document.h"
#include "render/renderer.h"

namespace ink_engine {

// Writes the selected notebook pages with their native point sizes. The
// caller validates the range before calling this function.
bool ExportPdf(const Document &document, const Assets &assets, const char *title,
               size_t first_page, size_t page_count, bool include_hidden_layers,
               std::string *pdf);

}  // namespace ink_engine
