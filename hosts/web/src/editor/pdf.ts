import type { Engine } from "../engine/engine.ts";
import { createNotebook, type OpenNotebook } from "./notebook.ts";
import type { PdfReply, PdfRequest } from "./pdf.worker.ts";

export async function importPdf(
  engine: Engine, root: FileSystemDirectoryHandle, parent: string[],
  progress: (completed: number, total: number) => void,
): Promise<OpenNotebook | null> {
  const file = await new Promise<File | null>((resolve) => {
    const input = document.createElement("input");
    input.type = "file";
    input.accept = "application/pdf,.pdf";
    input.onchange = () => resolve(input.files?.item(0) ?? null);
    input.oncancel = () => resolve(null);
    input.click();
  });
  if (!file) return null;
  const worker = new Worker(new URL("./pdf.worker.ts", import.meta.url), { type: "module" });
  const request = (message: PdfRequest): Promise<PdfReply> => new Promise((resolve, reject) => {
    worker.onerror = (event) => reject(new Error(event.message || "PDF worker failed."));
    worker.onmessageerror = () => reject(new Error("Could not read the imported PDF page."));
    worker.onmessage = (event: MessageEvent<PdfReply>) => {
      if (event.data.kind === "error") reject(new Error(event.data.message));
      else resolve(event.data);
    };
    worker.postMessage(message, message.kind === "open" ? [message.bytes] : []);
  });
  let note: OpenNotebook | undefined;
  let completed = 0;
  try {
    const opened = await request({ kind: "open", bytes: await file.arrayBuffer() });
    if (opened.kind !== "opened" || opened.count === 0) throw new Error("The PDF has no pages.");
    progress(0, opened.count);
    for (let index = 0; index < opened.count; ++index) {
      const page = await request({ kind: "page", index });
      if (page.kind !== "page") throw new Error("The PDF worker returned no page.");
      if (!note) note = await createNotebook(engine, root, parent, file.name.replace(/\.pdf$/i, ""), "blank", "a4");
      note.document.importPageImage(index, page.png, page.width, page.height);
      if (index === 0) note.document.deletePage(1);
      await note.saver.save();
      completed++;
      progress(completed, opened.count);
    }
    return note!;
  } catch (error) {
    note?.document.free();
    throw new Error(`${String(error)}${note ? ` ${completed} imported pages remain in ${note.name}.` : ""}`);
  } finally {
    worker.terminate();
  }
}
