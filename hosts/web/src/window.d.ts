import type { NotebookFile } from "./engine/engine.ts";

declare global {
  // The File System Observer API (Chromium 129+), which TypeScript's DOM
  // library does not declare yet. Follows the WHATWG proposal
  // github.com/whatwg/fs/blob/main/proposals/FileSystemObserver.md.
  class FileSystemObserver {
    constructor(callback: () => void);
    observe(handle: FileSystemHandle, options: { recursive: boolean }): Promise<void>;
    disconnect(): void;
  }

  interface Window {
    // With ?root=opfs: every file the page wrote, in order. The browser
    // tests compare the saved files with these bytes.
    mathNotesWrites?: NotebookFile[];
    // With ?root=opfs: thumbnail cache reads and engine renders
    // (src/storage/thumbnails.ts).
    mathNotesThumbnails?: { hits: number; renders: number };
  }
}
