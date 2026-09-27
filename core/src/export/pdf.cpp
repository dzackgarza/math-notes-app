#include "export/pdf.h"

#include <set>

#include "document/navigation.h"
#include "include/core/SkAnnotation.h"
#include "include/core/SkCanvas.h"
#include "include/core/SkData.h"
#include "include/core/SkDocument.h"
#include "include/core/SkStream.h"
#include "include/docs/SkPDFDocument.h"
#include "include/docs/SkPDFJpegHelpers.h"

namespace ink_engine {

bool ExportPdf(const Document &document, const Assets &assets, const char *title, size_t first_page,
               size_t page_count, bool include_hidden_layers, std::string *pdf,
               bool include_links) {
  SkDynamicMemoryWStream stream;
  // Skia docs/examples/PDF.cpp:8-27, include/docs/SkPDFJpegHelpers.h:29-34.
  // Fixed dates make the same document's export byte-reproducible.
  SkPDF::Metadata metadata = SkPDF::JPEG::MetadataWithCallbacks();
  metadata.fTitle = title;
  metadata.fCreator = "Math Notes";
  metadata.fCreation = {0, 2000, 1, 1, 0, 0, 0, 0};
  metadata.fModified = metadata.fCreation;
  sk_sp<SkDocument> output = SkPDF::MakeDocument(&stream, metadata);
  if (!output) return false;
  Renderer renderer(nullptr, assets);
  const auto marks = NavigationMarks(document, include_hidden_layers);
  std::set<std::string> destinations;
  if (include_links) {
    for (size_t p = first_page; p < first_page + page_count; ++p)
      destinations.insert(document.pages[p]->file);
    for (const auto &mark : marks)
      if (!mark.id.empty() && mark.page >= first_page && mark.page < first_page + page_count)
        destinations.insert(document.pages[mark.page]->file + "#" + mark.id);
  }
  // Write scribbleapp.cpp:2101-2125 ScribbleApp::writePDF; Xournal++
  // XojCairoPdfExport.cpp:127-157 exportPage: each page keeps its own size.
  for (size_t index = first_page; index < first_page + page_count; ++index) {
    const Page &page = *document.pages[index];
    SkCanvas *canvas = output->beginPage(float(page.width), float(page.height));
    if (!canvas) return false;
    renderer.DrawPageForExport(canvas, document, page, include_hidden_layers);
    if (include_links) {
      auto name = SkData::MakeWithCString(page.file.c_str());
      SkAnnotateNamedDestination(canvas, SkPoint::Make(0, 0), name.get());
      for (const auto &mark : marks) {
        if (mark.page != index) continue;
        const auto &b = mark.bounds;
        if (!mark.id.empty()) {
          auto id = SkData::MakeWithCString((page.file + "#" + mark.id).c_str());
          SkAnnotateNamedDestination(canvas, SkPoint::Make(b.left, b.top), id.get());
        } else {
          const auto target = PageLinkTarget(page, mark.href);
          auto data = SkData::MakeWithCString(target.c_str());
          const auto rect = SkRect::MakeLTRB(b.left, b.top, b.right, b.bottom);
          if (destinations.contains(target))
            SkAnnotateLinkToDestination(canvas, rect, data.get());
          else
            SkAnnotateRectWithURL(canvas, rect, data.get());
        }
      }
    }
    output->endPage();
  }
  output->close();
  pdf->resize(stream.bytesWritten());
  stream.copyTo(pdf->data());
  return !pdf->empty();
}

}  // namespace ink_engine
