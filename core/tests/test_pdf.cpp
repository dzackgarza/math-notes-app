// Skia PDF backend: Skia docs/examples/PDF.cpp.
#include <catch2/catch_test_macros.hpp>

#include <fstream>
#include <string>

#include "include/codec/SkCodec.h"
#include "include/codec/SkPngDecoder.h"
#include "include/core/SkBitmap.h"
#include "include/core/SkCanvas.h"
#include "include/core/SkData.h"
#include "include/core/SkDocument.h"
#include "include/core/SkImage.h"
#include "include/core/SkPaint.h"
#include "include/core/SkPath.h"
#include "include/core/SkStream.h"
#include "include/docs/SkPDFDocument.h"
#include "include/docs/SkPDFJpegHelpers.h"
#include "include/encode/SkPngEncoder.h"
#include "include/utils/SkParsePath.h"
#include "ink.h"
#include "support/session.h"

namespace {

constexpr SkScalar kA4Width = 595.276f;   // 210 mm in points
constexpr SkScalar kA4Height = 841.89f;   // 297 mm in points

sk_sp<SkData> encodedPng() {
  SkBitmap bitmap;
  bitmap.allocN32Pixels(16, 16);
  bitmap.eraseColor(SK_ColorBLUE);
  SkDynamicMemoryWStream png;
  REQUIRE(SkPngEncoder::Encode(&png, bitmap.pixmap(), {}));
  return png.detachAsData();
}

sk_sp<SkData> a4Pdf() {
  auto path = SkParsePath::FromSVGString("M100 100 L300 120 L200 300 Z");
  REQUIRE(path.has_value());
  auto codec = SkPngDecoder::Decode(encodedPng(), nullptr);
  REQUIRE(codec);
  auto [image, result] = codec->getImage();
  REQUIRE(result == SkCodec::kSuccess);

  SkDynamicMemoryWStream out;
  auto document = SkPDF::MakeDocument(&out, SkPDF::JPEG::MetadataWithCallbacks());
  REQUIRE(document);
  SkCanvas *canvas = document->beginPage(kA4Width, kA4Height);
  SkPaint paint;
  paint.setColor(SK_ColorBLACK);
  canvas->drawPath(*path, paint);
  canvas->drawImage(image, 400, 400);
  document->endPage();
  document->close();
  return out.detachAsData();
}

}  // namespace

TEST_CASE("Skia PDF writes a deterministic A4 page with a path and a PNG") {
  auto first = a4Pdf();
  auto second = a4Pdf();
  REQUIRE(first->size() > 0);
  REQUIRE(first->equals(second.get()));
  std::ofstream("a4.pdf", std::ios::binary)
      .write(static_cast<const char *>(first->data()), first->size());
}

TEST_CASE("A notebook exports a selected page range as a deterministic PDF") {
  ink_test::Session session;
  InkPenSample ink[] = {
      {.x = 100, .y = 100, .time = 0, .tool = INK_TOOL_PEN, .phase = INK_PHASE_BEGIN},
      {.x = 150, .y = 100, .time = 20, .id = 1, .tool = INK_TOOL_PEN, .phase = INK_PHASE_MOVE},
      {.x = 200, .y = 100, .time = 40, .id = 2, .tool = INK_TOOL_PEN, .phase = INK_PHASE_END}};
  REQUIRE(ink_input(session.get(), ink, 3) == INK_OK);
  REQUIRE(ink_document_set_page_size(session.document, INK_PAGE_LETTER, 0, 0) == INK_OK);
  REQUIRE(ink_document_insert_page(session.document, 1) == INK_OK);
  REQUIRE(ink_document_insert_page(session.document, 2) == INK_OK);
  const InkPdfExportSpec range{.first_page = 1, .page_count = 2};
  const uint8_t *bytes = nullptr;
  size_t size = 0;
  REQUIRE(ink_export_pdf(session.document, "Algebra", &range, &bytes, &size) == INK_OK);
  const std::string first(reinterpret_cast<const char *>(bytes), size);
  REQUIRE(first.starts_with("%PDF-"));
  REQUIRE(first.size() > 1000);

  REQUIRE(ink_export_pdf(session.document, "Algebra", &range, &bytes, &size) == INK_OK);
  CHECK(std::string(reinterpret_cast<const char *>(bytes), size) == first);
  std::ofstream("notebook-range.pdf", std::ios::binary).write(first.data(), first.size());

  const InkPdfExportSpec full{.first_page = 0, .page_count = 3};
  REQUIRE(ink_export_pdf(session.document, "Algebra", &full, &bytes, &size) == INK_OK);
  CHECK(size > first.size());
  std::ofstream("notebook-full.pdf", std::ios::binary)
      .write(reinterpret_cast<const char *>(bytes), size);
}
