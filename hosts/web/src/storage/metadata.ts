// The library metadata sidecar Notes/.library.json (docs/FORMAT.md, Other
// files): tags with their colors, and per note a favorite flag, tags and a
// description, keyed by the note's path from the root.
import type { Store } from "./store.ts";

export interface Tag {
  name: string;
  color: string;
}

export interface NoteMetadata {
  favorite: boolean;
  tags: string[];
  description: string;
}

export interface LibraryMetadata {
  tags: Tag[];
  notes: Record<string, NoteMetadata>;
}

const FILE = ".library.json";

// Stored with the keys in this order, as notebook.json is.
interface StoredMetadata {
  format: "math-notes-library";
  version: 1;
  tags: Tag[];
  notes: Record<string, NoteMetadata>;
}

export const emptyNote = (): NoteMetadata => ({ favorite: false, tags: [], description: "" });

// The tag colors offered in turn, from the spec's light palette.
export const TAG_COLORS = ["#2F6FEB", "#3FA35B", "#8B5CF6", "#F08A24", "#2BB3C0", "#D6455D", "#1F3A93", "#C084FC"];

export async function readMetadata(store: Store): Promise<LibraryMetadata> {
  const bytes = await store.read([FILE]);
  if (!bytes) return { tags: [], notes: {} };
  const stored = JSON.parse(new TextDecoder().decode(bytes)) as StoredMetadata;
  return { tags: stored.tags, notes: stored.notes };
}

export async function writeMetadata(store: Store, metadata: LibraryMetadata): Promise<void> {
  const stored: StoredMetadata = { format: "math-notes-library", version: 1, tags: metadata.tags, notes: metadata.notes };
  const bytes = new TextEncoder().encode(`${JSON.stringify(stored, null, 2)}\n`);
  await store.write([FILE], bytes);
}

// The metadata after the notebook or folder at `from` moved to `to`: the
// entries of the notes under it follow them to their new paths.
export function moveNotes(metadata: LibraryMetadata, from: readonly string[], to: readonly string[]): LibraryMetadata {
  const prefix = from.join("/");
  const notes: Record<string, NoteMetadata> = {};
  for (const [key, note] of Object.entries(metadata.notes)) {
    const inside = key === prefix || key.startsWith(`${prefix}/`);
    notes[inside ? to.join("/") + key.slice(prefix.length) : key] = note;
  }
  return { ...metadata, notes };
}
