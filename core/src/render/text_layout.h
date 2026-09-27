#pragma once

#include "document/document.h"
#include "modules/skparagraph/include/Paragraph.h"

namespace ink_engine {
struct TextLayout {
  std::unique_ptr<skia::textlayout::Paragraph> paragraph;
  std::vector<skia::textlayout::LineMetrics> lines;
  std::string source;
};
// Skia Paragraph owns shaping, bidi runs, wrapping, and baseline metrics.
TextLayout LayoutText(const Text &text);
bool HasText(const Page &page);
}  // namespace ink_engine
