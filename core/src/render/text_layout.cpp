#include "render/text_layout.h"

#include <cmath>
#include <stdexcept>

#include "modules/skparagraph/include/ParagraphBuilder.h"
#include "modules/skunicode/include/SkUnicode_icu.h"
#include "render/text_font.h"

namespace ink_engine {
namespace {
bool ContainsText(const Elements &elements) {
  for (const auto &element : elements) {
    const bool found = std::visit(
        [](const auto &value) {
          using T = std::decay_t<decltype(value)>;
          if constexpr (std::is_same_v<T, Text>)
            return true;
          else if constexpr (std::is_same_v<T, Bookmark> || std::is_same_v<T, Link> ||
                             std::is_same_v<T, Figure>)
            return ContainsText(value.children);
          else
            return false;
        },
        element->value);
    if (found) return true;
  }
  return false;
}
}  // namespace

bool HasText(const Page &page) {
  for (const auto &layer : page.layers)
    if (ContainsText(layer.elements)) return true;
  return false;
}

TextLayout LayoutText(const Text &text) {
  // Same ownership as Skia modules/skparagraph/samples and Flutter's paragraph builder.
  using namespace skia::textlayout;
  static sk_sp<FontCollection> fonts = [] {
    auto collection = sk_make_sp<FontCollection>();
    collection->setDefaultFontManager(TextFontManager(), "Noto Sans");
    return collection;
  }();
  static sk_sp<SkUnicode> unicode = SkUnicodes::ICU::Make();
  if (!unicode) throw std::runtime_error("Skia Unicode initialization failed");
  TextStyle style;
  style.setFontFamilies({SkString("Noto Sans"), SkString("Noto Sans Arabic"),
                         SkString("Noto Sans Hebrew"), SkString("Noto Sans Devanagari"),
                         SkString("Noto Sans Symbols 2")});
  style.setFontSize(text.size);
  style.setHeight(1.2);
  style.setHeightOverride(true);
  style.setColor(SkColorSetRGB(text.fill.r, text.fill.g, text.fill.b));
  ParagraphStyle paragraph_style;
  paragraph_style.setTextStyle(style);
  paragraph_style.setTextAlign(TextAlign::kStart);
  paragraph_style.setTextDirection(text.rtl ? TextDirection::kRtl : TextDirection::kLtr);
  auto builder = ParagraphBuilder::make(paragraph_style, fonts, unicode);
  TextLayout layout;
  for (size_t i = 0; i < text.lines.size(); ++i) {
    if (i) layout.source += '\n';
    layout.source += text.lines[i];
  }
  builder->addText(layout.source.data(), layout.source.size());
  layout.paragraph = builder->Build();
  layout.paragraph->layout(text.width > 0 ? text.width : 1000000);
  if (text.width == 0)
    layout.paragraph->layout(
        std::max(1.0, std::ceil(double(layout.paragraph->getMaxIntrinsicWidth()))));
  layout.paragraph->getLineMetrics(layout.lines);
  return layout;
}
}  // namespace ink_engine
