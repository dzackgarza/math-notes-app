// The notes root as a host storage service (docs/ARCHITECTURE.md, Rules):
// the directory tree of docs/FORMAT.md, addressed by path segments from the
// root. Chromium reaches it through the File System Access API; Firefox and
// Safari through a WebDAV server (docs/FORMAT.md, Access per host).
import { createClient, type FileStat, type WebDAVClient } from "webdav";

export type Path = readonly string[];
export type Bytes = Uint8Array<ArrayBuffer>;

export interface Entry {
  name: string;
  kind: "file" | "directory";
  // ms since epoch; 0 when the store has none (File System Access directories).
  modified: number;
  size: number;
  // The server's entity tag, for the change check of #28; null without one.
  etag: string | null;
}

export interface Store {
  // What the settings show as the notes folder.
  readonly name: string;
  // The entries of directory `dir`, or null when it does not exist.
  list(dir: Path): Promise<Entry[] | null>;
  stat(path: Path): Promise<Entry | null>;
  // The file's bytes, or null when it does not exist.
  read(file: Path): Promise<Bytes | null>;
  // Replaces or creates the file, creating its directories.
  write(file: Path, bytes: Bytes): Promise<void>;
  // Removes a file, or a directory with its contents; nothing when absent.
  remove(path: Path): Promise<void>;
  // Creates the directory and its parents; nothing when it exists.
  makeDirectory(dir: Path): Promise<void>;
  // Moves a file or directory to `to`, which must not exist.
  move(from: Path, to: Path): Promise<void>;
}

// The temporary file of an atomic write of `name`: Chromium's name for its
// swap file, which scans skip on every host (docs/FORMAT.md, Access per host).
export const SWAP_SUFFIX = ".crswap";

function notFound(e: unknown): boolean {
  return e instanceof DOMException && (e.name === "NotFoundError" || e.name === "TypeMismatchError");
}

// Chromium's exclusive writer: no other writer of the file while this one is
// open. Not yet in the File System Access type definitions.
type ExclusiveWritableOptions = FileSystemCreateWritableOptions & { mode: "exclusive" };

// A directory handle from the File System Access API (Chrome's articles "The
// File System Access API" and "Persistent permissions for the File System
// Access API"), or the origin-private file system in the automated tests.
export class FolderStore implements Store {
  readonly handle: FileSystemDirectoryHandle;
  readonly name: string;

  constructor(handle: FileSystemDirectoryHandle) {
    this.handle = handle;
    this.name = handle.name;
  }

  private async directory(dir: Path, create = false): Promise<FileSystemDirectoryHandle | null> {
    let handle = this.handle;
    try {
      for (const part of dir) handle = await handle.getDirectoryHandle(part, { create });
      return handle;
    } catch (e) {
      if (notFound(e)) return null;
      throw e;
    }
  }

  private async file(path: Path): Promise<File | null> {
    const dir = await this.directory(path.slice(0, -1));
    if (!dir) return null;
    try {
      return await (await dir.getFileHandle(path[path.length - 1])).getFile();
    } catch (e) {
      if (notFound(e)) return null;
      throw e;
    }
  }

  async list(dir: Path): Promise<Entry[] | null> {
    const handle = await this.directory(dir);
    if (!handle) return null;
    const entries: Entry[] = [];
    for await (const [name, child] of handle.entries()) {
      if (child.kind === "directory") {
        entries.push({ name, kind: "directory", modified: 0, size: 0, etag: null });
        continue;
      }
      const file = await child.getFile();
      entries.push({ name, kind: "file", modified: file.lastModified, size: file.size, etag: null });
    }
    return entries;
  }

  async stat(path: Path): Promise<Entry | null> {
    if (path.length === 0) return { name: this.name, kind: "directory", modified: 0, size: 0, etag: null };
    const name = path[path.length - 1];
    const file = await this.file(path);
    if (file) return { name, kind: "file", modified: file.lastModified, size: file.size, etag: null };
    return (await this.directory(path)) ? { name, kind: "directory", modified: 0, size: 0, etag: null } : null;
  }

  async read(path: Path): Promise<Bytes | null> {
    const file = await this.file(path);
    return file ? new Uint8Array(await file.arrayBuffer()) : null;
  }

  async write(path: Path, bytes: Bytes): Promise<void> {
    const dir = (await this.directory(path.slice(0, -1), true))!;
    const handle = await dir.getFileHandle(path[path.length - 1], { create: true });
    const options: ExclusiveWritableOptions = { keepExistingData: false, mode: "exclusive" };
    const writable = await handle.createWritable(options);
    await writable.write(bytes);
    await writable.close();
  }

  async remove(path: Path): Promise<void> {
    const dir = await this.directory(path.slice(0, -1));
    await dir?.removeEntry(path[path.length - 1], { recursive: true }).catch((e: unknown) => {
      if (!notFound(e)) throw e;
    });
  }

  async makeDirectory(dir: Path): Promise<void> {
    await this.directory(dir, true);
  }

  // File System Access has no directory move outside the origin-private file
  // system (FileSystemHandle.move moves files only), so a move is a copy,
  // then the removal of the source.
  async move(from: Path, to: Path): Promise<void> {
    const copy = async (source: Path, target: Path): Promise<void> => {
      const entries = await this.list(source);
      if (!entries) {
        await this.write(target, (await this.read(source))!);
        return;
      }
      await this.makeDirectory(target);
      for (const entry of entries) await copy([...source, entry.name], [...target, entry.name]);
    };
    await copy(from, to);
    await this.remove(from);
  }
}

export const DEFAULT_WEBDAV_URL = "http://127.0.0.1:31415";

// A WebDAV server that serves the notes root: `rclone serve webdav` on
// localhost (README.md, "Web app on this machine"), through the webdav client
// (perry-mitchell/webdav-client 5.11, README "Usage" and source/operations/).
// No request carries If-Match or If-None-Match: rclone's CORS preflight does
// not allow them (TRAPS.md).
export class WebDavStore implements Store {
  readonly url: string;
  readonly name: string;
  private readonly client: WebDAVClient;

  constructor(url: string) {
    this.url = url;
    this.name = url;
    this.client = createClient(url);
  }

  private static href(path: Path): string {
    return `/${path.join("/")}`;
  }

  private static entry(stat: FileStat): Entry {
    return {
      name: stat.basename,
      kind: stat.type,
      modified: Date.parse(stat.lastmod) || 0,
      size: stat.size,
      etag: stat.etag,
    };
  }

  private static missing(e: unknown): boolean {
    return (e as { status?: number }).status === 404;
  }

  async list(dir: Path): Promise<Entry[] | null> {
    try {
      const stats = (await this.client.getDirectoryContents(WebDavStore.href(dir))) as FileStat[];
      return stats.map(WebDavStore.entry);
    } catch (e) {
      if (WebDavStore.missing(e)) return null;
      throw e;
    }
  }

  // The ETag comes from the PROPFIND body: rclone sends no
  // Access-Control-Expose-Headers, so response headers are unreadable.
  async stat(path: Path): Promise<Entry | null> {
    try {
      return WebDavStore.entry((await this.client.stat(WebDavStore.href(path))) as FileStat);
    } catch (e) {
      if (WebDavStore.missing(e)) return null;
      throw e;
    }
  }

  async read(path: Path): Promise<Bytes | null> {
    try {
      const data = (await this.client.getFileContents(WebDavStore.href(path), { format: "binary" })) as ArrayBuffer;
      return new Uint8Array(data);
    } catch (e) {
      if (WebDavStore.missing(e)) return null;
      throw e;
    }
  }

  // A PUT to a temporary name in the same directory, then a MOVE over the
  // target: a write that stops between the two leaves the target intact.
  async write(path: Path, bytes: Bytes): Promise<void> {
    await this.makeDirectory(path.slice(0, -1));
    const target = WebDavStore.href(path);
    const swap = target + SWAP_SUFFIX;
    await this.client.putFileContents(swap, bytes, { contentLength: false });
    await this.client.moveFile(swap, target, { overwrite: true });
  }

  async remove(path: Path): Promise<void> {
    try {
      await this.client.deleteFile(WebDavStore.href(path));
    } catch (e) {
      if (!WebDavStore.missing(e)) throw e;
    }
  }

  async makeDirectory(dir: Path): Promise<void> {
    if (dir.length === 0) return;
    await this.client.createDirectory(WebDavStore.href(dir), { recursive: true });
  }

  async move(from: Path, to: Path): Promise<void> {
    await this.client.moveFile(WebDavStore.href(from), WebDavStore.href(to), { overwrite: false });
  }
}
