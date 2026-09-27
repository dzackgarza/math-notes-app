// The library metadata sidecar Notes/.library.json (docs/FORMAT.md, Other
// files): tags with their colors, and per note a favorite flag, tags and a
// description, keyed by the note's path from the root.
import { writeFiles } from "./folder.ts";

export interface Tag {
  name: string;
  color: string;
}

export interface NoteMetadata {
  favorite: boolean;
  tags: string[];
  description: string;
}

export interface FolderMetadata {
  description: string;
  paper: string;
  coverColor: string;
  coverStyle: "classic" | "spine";
  tags: string[];
}

export interface LibraryMetadata {
  tags: Tag[];
  notes: Record<string, NoteMetadata>;
  folders: Record<string, FolderMetadata>;
  startingTemplates: StartingTemplate[];
  draft?: NoteDraft;
}

export type PageSizeSetting = "a4" | "letter";

export interface StartingTemplate {
  name: string;
  folder: string[];
  paper: string;
  pageSize: PageSizeSetting;
  tags: string[];
}

export interface NoteDraft {
  folder: string[];
  title: string;
  template: string;
  tags: string[];
  pageSize?: PageSizeSetting;
}

const FILE = ".library.json";

// Stored with the keys in this order, as notebook.json is.
interface StoredMetadata {
  format: "math-notes-library";
  version: 1;
  tags: Tag[];
  notes: Record<string, NoteMetadata>;
  folders?: Record<string, FolderMetadata>;
  startingTemplates?: StartingTemplate[];
  draft?: NoteDraft;
}

export const emptyNote = (): NoteMetadata => ({ favorite: false, tags: [], description: "" });
export const emptyFolder = (): FolderMetadata => ({ description: "", paper: "dotted", coverColor: "#A9C1F5", coverStyle: "classic", tags: [] });

// The tag colors offered in turn, from the spec's light palette.
export const TAG_COLORS = ["#2F6FEB", "#3FA35B", "#8B5CF6", "#F08A24", "#2BB3C0", "#D6455D", "#1F3A93", "#C084FC"];

export async function readMetadata(root: FileSystemDirectoryHandle): Promise<LibraryMetadata> {
  let text: string;
  try {
    text = await (await (await root.getFileHandle(FILE)).getFile()).text();
  } catch (e) {
    if (e instanceof DOMException && e.name === "NotFoundError") return { tags: [], notes: {}, folders: {}, startingTemplates: [] };
    throw e;
  }
  const stored = JSON.parse(text) as StoredMetadata;
  return { tags: stored.tags, notes: stored.notes, folders: stored.folders ?? {}, startingTemplates: stored.startingTemplates ?? [], draft: stored.draft };
}

export async function writeMetadata(root: FileSystemDirectoryHandle, metadata: LibraryMetadata): Promise<void> {
  const stored: StoredMetadata = { format: "math-notes-library", version: 1, tags: metadata.tags, notes: metadata.notes, folders: metadata.folders, startingTemplates: metadata.startingTemplates, draft: metadata.draft };
  const bytes = new TextEncoder().encode(`${JSON.stringify(stored, null, 2)}\n`);
  await writeFiles(root, [{ kind: "write", path: FILE, bytes }]);
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
  const folders: Record<string, FolderMetadata> = {};
  for (const [key, folder] of Object.entries(metadata.folders)) {
    const inside = key === prefix || key.startsWith(`${prefix}/`);
    folders[inside ? to.join("/") + key.slice(prefix.length) : key] = folder;
  }
  const draft = metadata.draft;
  const inMovedFolder = draft && draft.folder.length >= from.length && from.every((part, i) => draft.folder[i] === part);
  const startingTemplates = metadata.startingTemplates.map((template) => {
    const inside = template.folder.length >= from.length && from.every((part, i) => template.folder[i] === part);
    return inside ? { ...template, folder: [...to, ...template.folder.slice(from.length)] } : template;
  });
  return { ...metadata, notes, folders, startingTemplates, draft: inMovedFolder ? { ...draft, folder: [...to, ...draft.folder.slice(from.length)] } : draft };
}
