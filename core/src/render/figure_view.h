#pragma once
#include <string_view>

#include "modules/svg/include/SkSVGDOM.h"

namespace ink_engine {
sk_sp<SkSVGDOM> ParseFigureView(std::string_view svg);
}  // namespace ink_engine
