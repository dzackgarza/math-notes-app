import { expect, test } from "vitest";

import { loadEngine } from "../engine/load.ts";
import { readNotebook } from "../storage/folder.ts";
import { Saver } from "./notebook.ts";

test("pending notebook edits can be saved after a filesystem writer releases its lock", async () => {
  const engine = await loadEngine();
  const root = await navigator.storage.getDirectory();
  const name = `test-save-recovery-${crypto.randomUUID()}`;
  const dir = await root.getDirectoryHandle(name, { create: true });
  const document = engine.createBuiltinTemplate("dotted", 731n);
  const saver = new Saver(document, dir);
  try {
    await saver.save();
    const metadata = await dir.getFileHandle("notebook.json");
    const options: FileSystemCreateWritableOptions & { mode: "exclusive" } = {
      keepExistingData: true,
      mode: "exclusive",
    };
    const writer = await metadata.createWritable(options);
    document.insertPage(1);
    try {
      await expect(saver.save()).rejects.toMatchObject({ name: "NoModificationAllowedError" });
    } finally {
      await writer.close();
    }
    await saver.save();
    const saved = await readNotebook(dir);
    const reopened = engine.createDocument(732n);
    try {
      reopened.loadNotebook(saved.notebookJson);
      for (const page of saved.pages) reopened.loadPage(page.path, page.bytes);
      expect(reopened.pageCount()).toBe(2);
      expect(saved.pages.map((page) => page.path).sort()).toEqual(["pages/0001.svg", "pages/0002.svg"]);
      expect(reopened.contentSize()).toEqual(document.contentSize());
    } finally {
      reopened.free();
    }
  } finally {
    document.free();
    await root.removeEntry(name, { recursive: true });
  }
});
