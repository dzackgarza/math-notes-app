import type { Engine } from "../engine/engine.ts";
import { openNotebook, Saver, type OpenNotebook } from "./notebook.ts";

export interface Clipping { id: string; png: Uint8Array<ArrayBuffer> }
// Shapes in the engine's page format (ReadShape in core/src/format/
// page_svg.cpp): it has an ellipse and no circle, and it reads the stroke
// from each shape.
const outline = 'fill="none" stroke="#000000" stroke-width="1.4"';
const shapes = [
  `<ellipse cx="30" cy="30" rx="27" ry="27" ${outline}/>`,
  `<rect x="3" y="3" width="54" height="54" ${outline}/>`,
  `<polygon points="30,3 57,57 3,57" ${outline}/>`,
  `<polygon points="3,30 16.5,6.6 43.5,6.6 57,30 43.5,53.4 16.5,53.4" ${outline}/>`,
];

async function withClippings<T>(engine: Engine, root: FileSystemDirectoryHandle, action: (note: OpenNotebook) => Promise<T>): Promise<T> {
  return await navigator.locks.request("math-notes-clippings", async () => {
    try { await root.getDirectoryHandle(".clippings"); }
    catch (error) {
      if (!(error instanceof DOMException && error.name === "NotFoundError")) throw error;
      const document = engine.createDocument(crypto.getRandomValues(new BigUint64Array(1))[0]);
      try {
        document.deletePage(0);
        // Write res_ui.cpp:211-254 supplies these first-use geometric clippings.
        for (const shape of shapes) document.addClipping(`<svg xmlns="http://www.w3.org/2000/svg" width="60" height="60"><g id="clipping">${shape}</g></svg>`);
        const dir = await root.getDirectoryHandle(".clippings", { create: true });
        await new Saver(document, dir, []).save();
      } finally { document.free(); }
    }
    const note = await openNotebook(engine, root, [".clippings"]);
    try { return await action(note); }
    finally { note.document.free(); }
  });
}

async function pages(note: OpenNotebook): Promise<{ id: string }[]> {
  return (JSON.parse(await (await (await note.dir.getFileHandle("notebook.json")).getFile()).text()) as { pages: { id: string }[] }).pages;
}

async function indexOf(note: OpenNotebook, id: string): Promise<number> {
  const index = (await pages(note)).findIndex((page) => page.id === id);
  if (index < 0) throw new Error("This clipping was removed. Refresh the panel.");
  return index;
}

export function listClippings(engine: Engine, root: FileSystemDirectoryHandle): Promise<Clipping[]> {
  return withClippings(engine, root, async (note) => (await pages(note)).map((page, index) => ({ id: page.id, png: note.document.pagePng(index, 240) })));
}

export function saveClipping(engine: Engine, root: FileSystemDirectoryHandle, svg: string): Promise<void> {
  return withClippings(engine, root, async (note) => {
    note.document.addClipping(svg);
    await note.saver.save();
  });
}

export function clippingSvg(engine: Engine, root: FileSystemDirectoryHandle, id: string): Promise<string> {
  return withClippings(engine, root, async (note) => note.document.clippingSvg(await indexOf(note, id)));
}

export function changeClipping(engine: Engine, root: FileSystemDirectoryHandle, id: string, action: "up" | "down" | "delete"): Promise<void> {
  return withClippings(engine, root, async (note) => {
    const index = await indexOf(note, id);
    if (action === "delete") note.document.deletePage(index);
    else {
      const target = index + (action === "up" ? -1 : 1);
      if (target < 0 || target >= note.document.pageCount()) return;
      note.document.movePage(index, target);
    }
    await note.saver.save();
  });
}
