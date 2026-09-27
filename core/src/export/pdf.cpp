#include "export/pdf.h"

#include "include/core/SkCanvas.h"
#include "include/core/SkDocument.h"
#include "include/core/SkStream.h"
#include "include/docs/SkPDFDocument.h"
#include "include/docs/SkPDFJpegHelpers.h"

namespace ink_engine {

bool ExportPdf(const Document &document, const Assets &assets, const char *title,
               size_t first_page, size_t page_count, bool include_hidden_layers,
               std::string *pdf) {
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
  // Write scribbleapp.cpp:2101-2125 ScribbleApp::writePDF; Xournal++
  // XojCairoPdfExport.cpp:127-157 exportPage: each page keeps its own size.
  for (size_t index = first_page; index < first_page + page_count; ++index) {
    const Page &page = *document.pages[index];
    SkCanvas *canvas = output->beginPage(float(page.width), float(page.height));
    if (!canvas) return false;
    renderer.DrawPageForExport(canvas, document, page, include_hidden_layers);
    output->endPage();
  }
  output->close();
  pdf->resize(stream.bytesWritten());
  stream.copyTo(pdf->data());
  return !pdf->empty();
}

}  // namespace ink_engine
