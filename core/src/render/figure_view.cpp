#include "render/figure_view.h"

#include <stdexcept>

#include "include/codec/SkCodec.h"
#include "include/codec/SkJpegDecoder.h"
#include "include/codec/SkPngDecoder.h"
#include "include/core/SkStream.h"
#include "modules/skresources/include/SkResources.h"

namespace ink_engine {
sk_sp<SkSVGDOM> ParseFigureView(std::string_view svg) {
  // Skia SVG DOM and its data URI resource provider own the compiled SVG view.
  static const bool registered = [] {
    SkCodecs::Register(SkPngDecoder::Decoder());
    SkCodecs::Register(SkJpegDecoder::Decoder());
    return true;
  }();
  (void)registered;
  SkMemoryStream stream(svg.data(), svg.size());
  auto dom = SkSVGDOM::Builder()
                 .setResourceProvider(skresources::DataURIResourceProviderProxy::Make(nullptr))
                 .make(stream);
  if (!dom) throw std::invalid_argument("the compiled figure is not a valid SVG");
  return dom;
}
}  // namespace ink_engine
