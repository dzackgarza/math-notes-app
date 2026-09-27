#pragma once

#include "format/notebook.h"
#include "include/core/SkFontMgr.h"

namespace ink_engine {

// The fonts shared by page rendering and text selection geometry.
sk_sp<SkFontMgr> TextFontManager();
const NotebookFiles &TextFontFiles();
std::string TextFontCss();

}  // namespace ink_engine
