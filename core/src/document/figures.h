#pragma once
#include "document/document.h"

namespace ink_engine {
struct FigureLocation {
  const Figure *figure = nullptr;
  size_t page = 0, layer = 0;
};
FigureLocation FindFigure(const Document &document, const std::string &id);
Document SetFigureDraft(Document document, const std::string &id, const std::string &href);
Document ReplaceFigure(Document document, const Figure &figure);
}  // namespace ink_engine
