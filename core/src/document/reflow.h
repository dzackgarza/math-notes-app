#pragma once
#include "document/pages.h"

namespace ink_engine {
enum class SpaceMode { kVertical, kHorizontal, kRuled };
// Write Selection::insertSpace/reflowStrokes, extended across fixed pages.
// All changed pages form one value for the editor's history.
Document InsertSpace(Document document, size_t page, Point start, Point end, SpaceMode mode,
                     IdGenerator &ids, const std::optional<Page> &template_page);
}  // namespace ink_engine
