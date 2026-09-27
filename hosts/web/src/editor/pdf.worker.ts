// MuPDF's documented page rendering API owns PDF parsing and rasterization:
// https://github.com/ArtifexSoftware/mupdf.js#quick-start
import * as mupdf from "mupdf";

export type PdfRequest = { kind: "open"; bytes: ArrayBuffer } | { kind: "page"; index: number };
export type PdfReply =
  | { kind: "opened"; count: number }
  | { kind: "page"; png: Uint8Array; width: number; height: number }
  | { kind: "error"; message: string };

let pdf: mupdf.Document | undefined;
self.onmessage = (event: MessageEvent<PdfRequest>) => {
  try {
    if (event.data.kind === "open") {
      pdf = mupdf.Document.openDocument(event.data.bytes, "application/pdf");
      if (pdf.needsPassword()) throw new Error("Open an unencrypted PDF to import it.");
      self.postMessage({ kind: "opened", count: pdf.countPages() } satisfies PdfReply);
      return;
    }
    if (!pdf) throw new Error("No PDF is open.");
    const page = pdf.loadPage(event.data.index);
    try {
      const [x0, y0, x1, y1] = page.getBounds();
      const width = x1 - x0, height = y1 - y0;
      const scale = 4128 / width;
      const pixmap = page.toPixmap(mupdf.Matrix.scale(scale, scale), mupdf.ColorSpace.DeviceRGB, false, true);
      try {
        const png = pixmap.asPNG().slice();
        self.postMessage({ kind: "page", png, width, height } satisfies PdfReply, { transfer: [png.buffer] });
      } finally {
        pixmap.destroy();
      }
    } finally {
      page.destroy();
    }
  } catch (error) {
    self.postMessage({ kind: "error", message: String(error) } satisfies PdfReply);
  }
};
