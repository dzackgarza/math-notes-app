#pragma once
#include <cstddef>
#include "document/document.h"
#include "document/ids.h"

namespace ink_engine {
Document AddLayer(Document document, IdGenerator &ids, std::string name);
Document SetLayer(Document document, size_t index, std::string name, bool hidden, bool locked);
Document MoveLayer(Document document, size_t from, size_t to);
Document RemoveLayer(Document document, size_t index, bool merge_down);
}  // namespace ink_engine
