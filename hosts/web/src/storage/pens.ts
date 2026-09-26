// The pen presets Notes/.pens.json (docs/FORMAT.md, Other files), shared by
// every device that opens the root. The engine reads and writes the file.
import type { Engine, Pen } from "../engine/engine.ts";
import type { Store } from "./store.ts";

const FILE = ".pens.json";

// The presets in the root; the defaults are written on first use.
export async function readPens(store: Store, engine: Engine): Promise<Pen[]> {
  let bytes = await store.read([FILE]);
  if (!bytes) {
    bytes = engine.defaultPens();
    await store.write([FILE], bytes);
  }
  return engine.readPens(bytes);
}

export async function writePens(store: Store, engine: Engine, pens: readonly Pen[]): Promise<void> {
  await store.write([FILE], engine.writePens(pens));
}
