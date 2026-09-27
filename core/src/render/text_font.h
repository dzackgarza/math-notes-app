#pragma once

#include "include/core/SkTypeface.h"

namespace ink_engine {

// The typeface shared by page rendering and text selection geometry.
sk_sp<SkTypeface> TextTypeface();

}  // namespace ink_engine
