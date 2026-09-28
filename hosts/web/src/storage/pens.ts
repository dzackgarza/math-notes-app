// The tool settings Notes/.pens.json (docs/FORMAT.md, Other files), shared by
// every device that opens the root. The engine reads and writes the file.
import type { Engine, PenFile } from "../engine/engine.ts";
import { writeFiles } from "./folder.ts";

const FILE = ".pens.json";

// The settings in the root; the defaults are written on first use.
export async function readPens(root: FileSystemDirectoryHandle, engine: Engine): Promise<PenFile> {
  let bytes: Uint8Array<ArrayBuffer>;
  try {
    bytes = new Uint8Array(await (await (await root.getFileHandle(FILE)).getFile()).arrayBuffer());
  } catch (e) {
    if (!(e instanceof DOMException && e.name === "NotFoundError")) throw e;
    bytes = engine.defaultPens();
    await writeFiles(root, [{ kind: "write", path: FILE, bytes }]);
  }
  return engine.readPens(bytes);
}

export async function writePens(root: FileSystemDirectoryHandle, engine: Engine, pens: PenFile): Promise<void> {
  await writeFiles(root, [{ kind: "write", path: FILE, bytes: engine.writePens(pens) }]);
}
