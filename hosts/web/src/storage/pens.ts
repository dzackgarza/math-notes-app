// The tool settings Notes/.pens.json (docs/FORMAT.md, Other files), shared by
// every device that opens the root. The engine reads and writes the file.
import type { Engine, PenFile } from "../engine/engine.ts";
import { writeFiles } from "./folder.ts";

const FILE = ".pens.json";

// The settings in the root. A folder without the file uses the default tools;
// the file is written only when the user changes a tool.
export async function readPens(root: FileSystemDirectoryHandle, engine: Engine): Promise<PenFile> {
  try {
    const bytes = new Uint8Array(await (await (await root.getFileHandle(FILE)).getFile()).arrayBuffer());
    return engine.readPens(bytes);
  } catch (e) {
    if (!(e instanceof DOMException && e.name === "NotFoundError")) throw e;
    return engine.readPens(engine.defaultPens());
  }
}

export async function writePens(root: FileSystemDirectoryHandle, engine: Engine, pens: PenFile): Promise<void> {
  await writeFiles(root, [{ kind: "write", path: FILE, bytes: engine.writePens(pens) }]);
}
