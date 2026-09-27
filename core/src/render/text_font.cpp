#include "render/text_font.h"

#include <stdexcept>

#include "include/core/SkData.h"
#include "include/core/SkFontMgr.h"
#include "include/core/SkFontStyle.h"
#include "include/ports/SkFontMgr_data.h"
#include "text_font.inc"

namespace ink_engine {

sk_sp<SkTypeface> TextTypeface() {
  // Skia CanvasKit's FontMgr.FromData uses a font manager backed by font
  // bytes. Both engine hosts load this same Noto Sans face from source.
  static sk_sp<SkTypeface> face = [] {
    sk_sp<SkData> bytes = SkData::MakeWithCopy(kTextFontData, sizeof kTextFontData);
    sk_sp<SkFontMgr> manager = SkFontMgr_New_Custom_Data(SkSpan<sk_sp<SkData>>(&bytes, 1));
    sk_sp<SkTypeface> typeface = manager->matchFamilyStyle("Noto Sans", SkFontStyle());
    if (!typeface) throw std::runtime_error("bundled Noto Sans typeface did not load");
    return typeface;
  }();
  return face;
}

}  // namespace ink_engine
