#include "render/text_font.h"

#include <vector>

#include "include/core/SkData.h"
#include "include/core/SkFontMgr.h"
#include "include/core/SkFontStyle.h"
#include "include/ports/SkFontMgr_data.h"
#include "text_font.inc"

namespace ink_engine {
namespace {
struct BundledFont {
  const char *family;
  const char *file;
  sk_sp<SkData> data;
};
const std::vector<BundledFont> &Fonts() {
  static const std::vector<BundledFont> fonts{
      {"Noto Sans", "mn-font-NotoSans.ttf",
       SkData::MakeWithoutCopy(kTextFontData, sizeof kTextFontData)},
      {"Noto Sans Arabic", "mn-font-NotoSansArabic.ttf",
       SkData::MakeWithoutCopy(kNotoSansArabic, sizeof kNotoSansArabic)},
      {"Noto Sans Hebrew", "mn-font-NotoSansHebrew.ttf",
       SkData::MakeWithoutCopy(kNotoSansHebrew, sizeof kNotoSansHebrew)},
      {"Noto Sans Devanagari", "mn-font-NotoSansDevanagari.ttf",
       SkData::MakeWithoutCopy(kNotoSansDevanagari, sizeof kNotoSansDevanagari)},
      {"Noto Sans Symbols 2", "mn-font-NotoSansSymbols2.ttf",
       SkData::MakeWithoutCopy(kNotoSansSymbols2, sizeof kNotoSansSymbols2)},
  };
  return fonts;
}
}  // namespace

const NotebookFiles &TextFontFiles() {
  static const NotebookFiles files = [] {
    NotebookFiles result;
    result["assets/mn-font-Apache.txt"] =
        std::string(reinterpret_cast<const char *>(kLICENSE), sizeof kLICENSE);
    result["assets/mn-font-OFL.txt"] =
        std::string(reinterpret_cast<const char *>(kOFL_txt), sizeof kOFL_txt);
    for (const auto &font : Fonts())
      result[std::string("assets/") + font.file] =
          std::string(static_cast<const char *>(font.data->data()), font.data->size());
    return result;
  }();
  return files;
}

std::string TextFontCss() {
  std::string css;
  for (const auto &font : Fonts())
    css += std::string("@font-face{font-family:'") + font.family + "';src:url('../assets/" +
           font.file + "')}\n";
  return css;
}

sk_sp<SkFontMgr> TextFontManager() {
  static sk_sp<SkFontMgr> manager = [] {
    std::vector<sk_sp<SkData>> fonts;
    for (const auto &font : Fonts()) fonts.push_back(font.data);
    return SkFontMgr_New_Custom_Data(SkSpan<sk_sp<SkData>>(fonts.data(), fonts.size()));
  }();
  return manager;
}

}  // namespace ink_engine
