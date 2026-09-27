import * as mupdf from 'mupdf';

export type FigurePdfReply = { svg: string; width: number; height: number } | { error: string };

self.onmessage = (event: MessageEvent<Uint8Array>) => {
  try {
    const document = mupdf.Document.openDocument(event.data, 'application/pdf');
    try {
      if (document.countPages() !== 1) throw new Error('A figure must compile to one PDF page.');
      const page = document.loadPage(0);
      const buffer = new mupdf.Buffer();
      // MuPDF 205b8cf4 writer.c routes this writer to its native SVG device.
      const writer = new mupdf.DocumentWriter(buffer, 'svg', 'text=path');
      try {
        const bounds = page.getBounds();
        const device = writer.beginPage(bounds);
        try { page.run(device, mupdf.Matrix.identity); }
        finally { device.destroy(); }
        writer.endPage();
        writer.close();
        self.postMessage({ svg: buffer.asString(), width: bounds[2] - bounds[0], height: bounds[3] - bounds[1] } satisfies FigurePdfReply);
      } finally { writer.destroy(); buffer.destroy(); page.destroy(); }
    } finally { document.destroy(); }
  } catch (error) {
    self.postMessage({ error: String(error) } satisfies FigurePdfReply);
  }
};
