// The tool settings Notes/.pens.json (docs/FORMAT.md, Other files), shared by
// every device that opens the root. The engine reads and writes the file.
import type { Engine, PenFile } from "../engine/engine.ts";
import { writeFiles } from "./folder.ts";

const FILE = ".pens.json";

// Creates the default settings on first use. Root preparation owns this write,
// so later editor reads never need an exclusive filesystem lock.
export async function ensurePens(root: FileSystemDirectoryHandle, engine: Engine): Promise<void> {
  try {
    await root.getFileHandle(FILE);
  } catch (e) {
    if (!(e instanceof DOMException && e.name === "NotFoundError")) throw e;
    await writeFiles(root, [{ kind: "write", path: FILE, bytes: engine.defaultPens() }]);
  }
}

// The settings in the root. prepareRoot has already ensured the file exists.
export async function readPens(root: FileSystemDirectoryHandle, engine: Engine): Promise<PenFile> {
  const bytes = new Uint8Array(await (await (await root.getFileHandle(FILE)).getFile()).arrayBuffer());
  return engine.readPens(bytes);
}

export async function writePens(root: FileSystemDirectoryHandle, engine: Engine, pens: PenFile): Promise<void> {
  await writeFiles(root, [{ kind: "write", path: FILE, bytes: engine.writePens(pens) }]);
}
