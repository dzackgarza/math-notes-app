// The library screen of docs/specs/tablet-ui.md: sidebar, folder cards with
// sort and grid/list toggle, and the detail pane of the selected folder. The
// sidebar's Search, Recent, Favorites and tag views are views of one table of
// notes (spec, "Relation to the current model", item 5).
import { Button } from "@kobalte/core/button";
import { Dialog } from "@kobalte/core/dialog";
import { DropdownMenu } from "@kobalte/core/dropdown-menu";
import { TextField } from "@kobalte/core/text-field";
import { ToggleGroup } from "@kobalte/core/toggle-group";
import {
  BookOpen,
  ChevronDown,
  ChevronRight,
  Clock,
  Ellipsis,
  Folder as FolderIcon,
  FolderOpen,
  LayoutGrid,
  List,
  Plus,
  Search,
  Settings,
  Star,
  Trash2,
} from "lucide-solid";
import { createMemo, createSignal, For, type JSX, Match, mergeProps, Show, Switch } from "solid-js";

import { compareBy, type Folder, MY_NOTES, nameError, type Note, pathKey, type Sort } from "../storage/library.ts";
import { emptyNote, type LibraryMetadata, type NoteMetadata, TAG_COLORS } from "../storage/metadata.ts";
import type { Store } from "../storage/store.ts";
import { Connect } from "./Connect.tsx";
import { NoteCover, type Thumbnails } from "./paper.tsx";

export type Section = "library" | "search" | "recent" | "favorites" | "trash" | "settings" | `tag:${string}`;

export interface LibraryProps {
  root: Store;
  folders: Folder[];
  trash: Note[];
  metadata: LibraryMetadata;
  section: Section;
  onSection: (section: Section) => void;
  selected: string[];
  onSelect: (folder: string[]) => void;
  onOpen: (note: Note) => void;
  onNewNotebook: () => void;
  onNewNote: (folder: string[]) => void;
  onMetadata: (change: (metadata: LibraryMetadata) => LibraryMetadata) => void;
  onTrash: (path: string[]) => void;
  onRename: (path: string[], name: string) => void;
  onMove: (path: string[], parent: string[]) => void;
  thumbnail: Thumbnails;
  onChooseFolder: () => void;
  onConnectWebDav: (url: string) => void;
}

const relative = new Intl.RelativeTimeFormat("en", { numeric: "auto" });
const UNITS: [Intl.RelativeTimeFormatUnit, number][] = [
  ["year", 365 * 86400e3],
  ["month", 30 * 86400e3],
  ["week", 7 * 86400e3],
  ["day", 86400e3],
  ["hour", 3600e3],
  ["minute", 60e3],
];

// "2 hours ago", "yesterday", "now".
export function ago(time: number): string {
  const elapsed = Date.now() - time;
  for (const [unit, ms] of UNITS) if (elapsed >= ms) return relative.format(-Math.floor(elapsed / ms), unit);
  return relative.format(0, "second");
}

export const noteCount = (n: number) => `${n} ${n === 1 ? "note" : "notes"}`;

export function AppMark() {
  return (
    <div class="app-mark" aria-hidden="true">
      𝒩
    </div>
  );
}

export type SidebarProps = Pick<LibraryProps, "folders" | "metadata" | "section" | "onSection" | "onMetadata">;

export function Sidebar(props: SidebarProps) {
  const notes = () => props.folders.flatMap((f) => f.notes);
  const tagCount = (tag: string) => notes().filter((n) => props.metadata.notes[pathKey(n.path)]?.tags.includes(tag)).length;
  const item = (section: Section, icon: JSX.Element, label: string, count?: () => number) => (
    <Button class="nav-item" aria-current={props.section === section ? "page" : undefined} onClick={() => props.onSection(section)}>
      {icon}
      <span>{label}</span>
      <Show when={count !== undefined}>
        <span class="nav-count">{count!()}</span>
      </Show>
    </Button>
  );
  const [adding, setAdding] = createSignal(false);
  const [tagName, setTagName] = createSignal("");
  const addTag = () => {
    const name = tagName().trim();
    if (!name || props.metadata.tags.some((t) => t.name === name)) return;
    props.onMetadata((m) => ({ ...m, tags: [...m.tags, { name, color: TAG_COLORS[m.tags.length % TAG_COLORS.length] }] }));
    setTagName("");
    setAdding(false);
  };
  return (
    <nav class="sidebar" aria-label="Library">
      <div class="brand">
        <AppMark />
        <div class="brand-name">Math Notes</div>
      </div>
      {item("library", <BookOpen size={18} />, "Library")}
      {item("search", <Search size={18} />, "Search")}
      {item("recent", <Clock size={18} />, "Recent")}
      {item("favorites", <Star size={18} />, "Favorites")}
      {item("trash", <Trash2 size={18} />, "Trash")}
      <div class="sidebar-heading">
        <span>Tags</span>
        <Button class="icon-button" aria-label="Add tag" onClick={() => setAdding(true)}>
          <Plus size={16} />
        </Button>
      </div>
      <For each={props.metadata.tags}>
        {(tag) =>
          item(
            `tag:${tag.name}`,
            <span class="tag-dot" style={{ background: tag.color }} />,
            tag.name,
            () => tagCount(tag.name),
          )
        }
      </For>
      <div class="sidebar-spacer" />
      {item("settings", <Settings size={18} />, "Settings")}
      <Dialog open={adding()} onOpenChange={setAdding}>
        <Dialog.Portal>
          <Dialog.Overlay class="dialog-overlay" />
          <Dialog.Content class="dialog">
            <Dialog.Title class="dialog-title">New Tag</Dialog.Title>
            <form
              onSubmit={(e) => {
                e.preventDefault();
                addTag();
              }}
            >
              <TextField value={tagName()} onChange={setTagName} class="field">
                <TextField.Label class="field-label">Name</TextField.Label>
                <TextField.Input class="input" />
              </TextField>
              <div class="dialog-actions">
                <Dialog.CloseButton class="button">Cancel</Dialog.CloseButton>
                <Button class="button primary" type="submit">
                  Add Tag
                </Button>
              </div>
            </form>
          </Dialog.Content>
        </Dialog.Portal>
      </Dialog>
    </nav>
  );
}

function TagChips(props: { metadata: LibraryMetadata; tags: string[] }) {
  const color = (name: string) => props.metadata.tags.find((t) => t.name === name)?.color ?? "#8A8F98";
  return (
    <div class="chips">
      <For each={props.tags}>
        {(tag) => (
          <span class="chip" style={{ "--chip": color(tag) }}>
            {tag}
          </span>
        )}
      </For>
    </div>
  );
}

// Rename or move a notebook or folder: the dialogs of EntryDialog.
interface EntryAction {
  kind: "rename" | "move";
  path: string[];
  folder: boolean;
}

// The library's props, with the sort order and the entry dialogs.
interface View extends LibraryProps {
  sort: Sort;
  onSort: (sort: Sort) => void;
  onAction: (action: EntryAction) => void;
}

// Rename…, Move to… and Move to Trash, in a note's or a folder's ⋯ menu.
function EntryItems(props: { path: string[]; folder: boolean; view: View }) {
  const act = (kind: EntryAction["kind"]) => props.view.onAction({ kind, path: props.path, folder: props.folder });
  return (
    <>
      <DropdownMenu.Item class="menu-item" onSelect={() => act("rename")}>
        Rename…
      </DropdownMenu.Item>
      <DropdownMenu.Item class="menu-item" onSelect={() => act("move")}>
        Move to…
      </DropdownMenu.Item>
      <DropdownMenu.Item class="menu-item danger" onSelect={() => props.view.onTrash(props.path)}>
        Move to Trash
      </DropdownMenu.Item>
    </>
  );
}

function MenuTrigger(props: { name: string }) {
  return (
    <DropdownMenu.Trigger class="icon-button" aria-label={`${props.name} actions`} onClick={(e: MouseEvent) => e.stopPropagation()}>
      <Ellipsis size={18} />
    </DropdownMenu.Trigger>
  );
}

// The ⋯ menu of a note: favorite, tags, rename, move, move to the trash.
function NoteMenu(props: { note: Note; view: View }) {
  const key = () => pathKey(props.note.path);
  const meta = (): NoteMetadata => props.view.metadata.notes[key()] ?? emptyNote();
  const change = (update: (note: NoteMetadata) => NoteMetadata) =>
    props.view.onMetadata((m) => ({ ...m, notes: { ...m.notes, [key()]: update(m.notes[key()] ?? emptyNote()) } }));
  return (
    <DropdownMenu>
      <MenuTrigger name={props.note.name} />
      <DropdownMenu.Portal>
        <DropdownMenu.Content class="menu">
          <DropdownMenu.CheckboxItem
            class="menu-item"
            checked={meta().favorite}
            onChange={(favorite) => change((n) => ({ ...n, favorite }))}
          >
            Favorite
          </DropdownMenu.CheckboxItem>
          <Show when={props.view.metadata.tags.length > 0}>
            <DropdownMenu.Sub>
              <DropdownMenu.SubTrigger class="menu-item">Tags</DropdownMenu.SubTrigger>
              <DropdownMenu.Portal>
                <DropdownMenu.SubContent class="menu">
                  <For each={props.view.metadata.tags}>
                    {(tag) => (
                      <DropdownMenu.CheckboxItem
                        class="menu-item"
                        checked={meta().tags.includes(tag.name)}
                        onChange={(on) =>
                          change((n) => ({ ...n, tags: on ? [...n.tags, tag.name] : n.tags.filter((t) => t !== tag.name) }))
                        }
                      >
                        <span class="tag-dot" style={{ background: tag.color }} /> {tag.name}
                      </DropdownMenu.CheckboxItem>
                    )}
                  </For>
                </DropdownMenu.SubContent>
              </DropdownMenu.Portal>
            </DropdownMenu.Sub>
          </Show>
          <Show when={props.note.path[0] !== ".trash"}>
            <DropdownMenu.Separator class="menu-separator" />
            <EntryItems path={props.note.path} folder={false} view={props.view} />
          </Show>
        </DropdownMenu.Content>
      </DropdownMenu.Portal>
    </DropdownMenu>
  );
}

function NoteRow(props: { note: Note; subtitle: string; view: View }) {
  const meta = () => props.view.metadata.notes[pathKey(props.note.path)];
  return (
    <li class="note-row">
      <Button class="note-open" onClick={() => props.view.onOpen(props.note)}>
        <NoteCover root={props.view.root} note={props.note} thumbnail={props.view.thumbnail} class="note-thumb" />
        <span class="note-text">
          <span class="note-title">
            {props.note.name}
            <Show when={meta()?.favorite}>
              <Star size={13} class="favorite-mark" aria-label="Favorite" />
            </Show>
          </span>
          <span class="note-summary">{meta()?.description || props.subtitle}</span>
          <span class="note-time">{ago(props.note.modified)}</span>
        </span>
      </Button>
      <NoteMenu note={props.note} view={props.view} />
    </li>
  );
}

// A folder's cover: its first note's page 1 (spec, "New Notebook").
function FolderCover(props: { folder: Folder; view: View; class: string }) {
  return (
    <Show when={[...props.folder.notes].sort(compareBy(props.view.sort))[0]} fallback={<div class={`paper-tile ${props.class} empty-cover`} />}>
      {(first) => <NoteCover root={props.view.root} note={first()} thumbnail={props.view.thumbnail} class={props.class} />}
    </Show>
  );
}

// The folders directly inside folder `parent`.
function subfolders(folders: readonly Folder[], parent: readonly string[]): Folder[] {
  const key = pathKey(parent);
  return folders.filter((f) => f.path.length === parent.length + 1 && pathKey(f.path.slice(0, -1)) === key);
}

const lastName = (path: readonly string[]) => (path.length === 0 ? MY_NOTES : path[path.length - 1]);

// The path from the root to the open folder; each step opens its folder.
function Breadcrumb(props: View) {
  const steps = () => [[], ...props.selected.map((_, i) => props.selected.slice(0, i + 1))];
  return (
    <nav class="breadcrumb" aria-label="Folder path">
      <For each={steps()}>
        {(path, i) => (
          <>
            <Show when={i() > 0}>
              <ChevronRight size={16} class="breadcrumb-separator" />
            </Show>
            <Button
              class="breadcrumb-step"
              aria-current={i() === steps().length - 1 ? "page" : undefined}
              onClick={() => props.onSelect(path)}
            >
              {lastName(path)}
            </Button>
          </>
        )}
      </For>
    </nav>
  );
}

// The open folder as GoodNotes and Noteful show one: its subfolders, then its
// notes, in one grid. A folder opens on a tap; a note opens in the editor.
function FolderView(props: View) {
  const [query, setQuery] = createSignal("");
  const [layout, setLayout] = createSignal<"grid" | "list">("grid");
  const matches = (name: string) => name.toLowerCase().includes(query().trim().toLowerCase());
  const folders = createMemo(() => subfolders(props.folders, props.selected).filter((f) => matches(lastName(f.path))).sort(compareBy(props.sort)));
  const notes = createMemo(() => {
    const here = props.folders.find((f) => pathKey(f.path) === pathKey(props.selected))?.notes ?? [];
    return here.filter((n) => matches(n.name)).sort(compareBy(props.sort));
  });
  const folderTags = (folder: Folder) => [
    ...new Set(folder.notes.flatMap((n) => props.metadata.notes[pathKey(n.path)]?.tags ?? [])),
  ];
  const folderMeta = (folder: Folder) => {
    const inner = subfolders(props.folders, folder.path).length;
    return inner > 0 ? `${noteCount(folder.notes.length)} · ${inner} ${inner === 1 ? "folder" : "folders"}` : noteCount(folder.notes.length);
  };
  return (
    <>
      <Breadcrumb {...props} />
      <div class="filters">
        <TextField value={query()} onChange={setQuery} class="search">
          <Search size={16} />
          <TextField.Input class="search-input" placeholder="Search this folder…" aria-label="Search this folder" />
        </TextField>
        <DropdownMenu>
          <DropdownMenu.Trigger class="select-button" aria-label="Sort">
            {props.sort === "name" ? "Name" : "Last Modified"} <ChevronDown size={14} />
          </DropdownMenu.Trigger>
          <DropdownMenu.Portal>
            <DropdownMenu.Content class="menu">
              <DropdownMenu.RadioGroup value={props.sort} onChange={(v) => props.onSort(v as Sort)}>
                <DropdownMenu.RadioItem class="menu-item" value="modified">
                  Last Modified
                </DropdownMenu.RadioItem>
                <DropdownMenu.RadioItem class="menu-item" value="name">
                  Name
                </DropdownMenu.RadioItem>
              </DropdownMenu.RadioGroup>
            </DropdownMenu.Content>
          </DropdownMenu.Portal>
        </DropdownMenu>
        <ToggleGroup class="segmented" value={layout()} onChange={(v) => v && setLayout(v as "grid" | "list")} aria-label="Layout">
          <ToggleGroup.Item class="segment" value="grid" aria-label="Grid">
            <LayoutGrid size={16} />
          </ToggleGroup.Item>
          <ToggleGroup.Item class="segment" value="list" aria-label="List">
            <List size={16} />
          </ToggleGroup.Item>
        </ToggleGroup>
      </div>
      <ul class={layout() === "grid" ? "cards" : "cards list"} aria-label="Notebooks">
        <For each={folders()}>
          {(folder) => (
            <li class="card folder-card">
              <Button class="card-open" aria-label={lastName(folder.path)} onClick={() => props.onSelect(folder.path)}>
                <FolderCover folder={folder} view={props} class="card-cover" />
                <span class="card-text">
                  <span class="card-title">
                    <FolderIcon size={15} class="folder-mark" /> {lastName(folder.path)}
                  </span>
                  <span class="card-meta">{folderMeta(folder)}</span>
                  <Show when={folder.modified > 0}>
                    <span class="card-meta">Modified {ago(folder.modified)}</span>
                  </Show>
                </span>
              </Button>
              <div class="card-footer">
                <TagChips metadata={props.metadata} tags={folderTags(folder)} />
                <DropdownMenu>
                  <MenuTrigger name={lastName(folder.path)} />
                  <DropdownMenu.Portal>
                    <DropdownMenu.Content class="menu">
                      <EntryItems path={folder.path} folder view={props} />
                    </DropdownMenu.Content>
                  </DropdownMenu.Portal>
                </DropdownMenu>
              </div>
            </li>
          )}
        </For>
        <For each={notes()}>
          {(note) => (
            <li class="card">
              <Button class="card-open" aria-label={note.name} onClick={() => props.onOpen(note)}>
                <NoteCover root={props.root} note={note} thumbnail={props.thumbnail} class="card-cover" />
                <span class="card-text">
                  <span class="card-title">{note.name}</span>
                  <span class="card-meta">Modified {ago(note.modified)}</span>
                </span>
              </Button>
              <div class="card-footer">
                <TagChips metadata={props.metadata} tags={props.metadata.notes[pathKey(note.path)]?.tags ?? []} />
                <NoteMenu note={note} view={props} />
              </div>
            </li>
          )}
        </For>
      </ul>
      <Show when={folders().length === 0 && notes().length === 0}>
        <p class="empty">{query().trim() ? "Nothing matches." : "This folder is empty."}</p>
      </Show>
    </>
  );
}

function DetailPane(props: View) {
  const folder = () => props.folders.find((f) => pathKey(f.path) === pathKey(props.selected));
  const [query, setQuery] = createSignal("");
  return (
    <Show when={folder()}>
      {(f) => (
        <aside class="detail" aria-label={`${f().name} notes`}>
          <FolderCover folder={f()} view={props} class="detail-cover" />
          <h2 class="detail-title">{lastName(f().path)}</h2>
          <div class="detail-meta">
            {noteCount(f().notes.length)}
            <Show when={f().modified > 0}> · Modified {ago(f().modified)}</Show>
          </div>
          <h3 class="detail-tab">Notes</h3>
          <TextField value={query()} onChange={setQuery} class="search">
            <Search size={16} />
            <TextField.Input class="search-input" placeholder="Search notes…" aria-label="Search notes" />
          </TextField>
          <ul class="note-list" aria-label="Notes">
            <For each={f().notes.filter((n) => n.name.toLowerCase().includes(query().trim().toLowerCase())).sort(compareBy(props.sort))}>
              {(note) => <NoteRow note={note} subtitle={f().name} view={props} />}
            </For>
          </ul>
          <Button class="button new-in" onClick={() => props.onNewNote(f().path)}>
            <Plus size={16} /> New Note in {lastName(f().path)}
          </Button>
        </aside>
      )}
    </Show>
  );
}

// Search, Recent, Favorites, a tag, or the trash: one list of notes.
function NoteTable(props: { view: View; title: string; notes: Note[]; search?: boolean }) {
  const [query, setQuery] = createSignal("");
  const folderName = (note: Note) =>
    props.view.folders.find((f) => f.notes.includes(note))?.name ?? (note.path[0] === ".trash" ? "Trash" : "");
  const shown = () => props.notes.filter((n) => n.name.toLowerCase().includes(query().trim().toLowerCase()));
  return (
    <>
      <Show when={props.search}>
        <div class="filters">
          <TextField value={query()} onChange={setQuery} class="search wide">
            <Search size={16} />
            <TextField.Input class="search-input" placeholder="Search notes by title…" aria-label="Search notes by title" autofocus />
          </TextField>
        </div>
      </Show>
      <ul class="note-list table" aria-label={props.title}>
        <For each={shown()} fallback={<li class="empty">No notes.</li>}>
          {(note) => <NoteRow note={note} subtitle={folderName(note)} view={props.view} />}
        </For>
      </ul>
    </>
  );
}

// The names in folder `parent` (path segments; [] is the root) that the scan
// found: its notes and its subfolders.
function namesIn(folders: readonly Folder[], parent: readonly string[]): string[] {
  const key = pathKey(parent);
  const notes = folders.find((f) => pathKey(f.path) === key)?.notes.map((n) => n.name) ?? [];
  const subfolders = folders.filter((f) => f.path.length === parent.length + 1 && pathKey(f.path.slice(0, -1)) === key);
  return [...notes, ...subfolders.map((f) => f.path[f.path.length - 1])];
}

// The rename dialog (a name field, checked as Write's NewDocDialog checks it)
// and the move dialog (the folders it can go to).
function EntryDialog(props: { action: EntryAction; view: View; onClose: () => void }) {
  const name = () => props.action.path[props.action.path.length - 1];
  const parent = () => props.action.path.slice(0, -1);
  const [text, setText] = createSignal(name());
  const error = () => (text().trim() === name() ? null : nameError(text(), namesIn(props.view.folders, parent())));
  // The folders a move can reach: not the current one, and for a folder not
  // itself or a folder inside it.
  const targets = () =>
    props.view.folders
      .map((f) => f.path)
      .filter((path) => pathKey(path) !== pathKey(parent()))
      .filter((path) => !(props.action.folder && path.length >= props.action.path.length && props.action.path.every((p, i) => path[i] === p)))
      .sort((a, b) => (a.length === 0 ? -1 : b.length === 0 ? 1 : pathKey(a).localeCompare(pathKey(b))));
  const title = () => `${props.action.kind === "rename" ? "Rename" : "Move"} ${props.action.folder ? "Notebook" : "Note"}`;
  return (
    <Dialog open onOpenChange={(open) => !open && props.onClose()}>
      <Dialog.Portal>
        <Dialog.Overlay class="dialog-overlay" />
        <Dialog.Content class="dialog">
          <Dialog.Title class="dialog-title">{title()}</Dialog.Title>
          <Show
            when={props.action.kind === "rename"}
            fallback={
              <>
                <p class="dialog-lede">Move “{name()}” to:</p>
                <ul class="move-targets" aria-label="Folders">
                  <For each={targets()} fallback={<li class="empty">No other folder.</li>}>
                    {(path) => (
                      <li>
                        <Button
                          class="move-target"
                          onClick={() => {
                            props.view.onMove(props.action.path, path);
                            props.onClose();
                          }}
                        >
                          <FolderOpen size={16} /> {path.length === 0 ? MY_NOTES : path.join(" / ")}
                        </Button>
                      </li>
                    )}
                  </For>
                </ul>
                <div class="dialog-actions">
                  <Dialog.CloseButton class="button">Cancel</Dialog.CloseButton>
                </div>
              </>
            }
          >
            <form
              onSubmit={(e) => {
                e.preventDefault();
                if (error()) return;
                if (text().trim() !== name()) props.view.onRename(props.action.path, text().trim());
                props.onClose();
              }}
            >
              <TextField value={text()} onChange={setText} validationState={error() ? "invalid" : "valid"} class="field">
                <TextField.Label class="field-label">Name</TextField.Label>
                <TextField.Input class="input" autofocus />
                <TextField.ErrorMessage class="field-error">{error()}</TextField.ErrorMessage>
              </TextField>
              <div class="dialog-actions">
                <Dialog.CloseButton class="button">Cancel</Dialog.CloseButton>
                <Button class="button primary" type="submit" disabled={error() !== null}>
                  Rename
                </Button>
              </div>
            </form>
          </Show>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog>
  );
}

export function Library(props: LibraryProps) {
  const [sort, setSort] = createSignal<Sort>("modified");
  const [action, setAction] = createSignal<EntryAction>();
  const view: View = mergeProps(props, {
    get sort() {
      return sort();
    },
    onSort: setSort,
    onAction: setAction,
  });
  const notes = () => props.folders.flatMap((f) => f.notes);
  const meta = (n: Note) => props.metadata.notes[pathKey(n.path)];
  const tag = () => (props.section.startsWith("tag:") ? props.section.slice(4) : "");
  const title = (): string => {
    const titles: Record<string, string> = {
      library: "Library",
      search: "Search",
      recent: "Recent",
      favorites: "Favorites",
      trash: "Trash",
      settings: "Settings",
    };
    return titles[props.section] ?? tag();
  };
  return (
    <div class="library">
      <Sidebar {...props} />
      <main class="main">
        <header class="main-header">
          <div>
            <h1>{title()}</h1>
            <Show when={props.section === "library"}>
              <p class="lede">A collection of mathematical notebooks.</p>
            </Show>
          </div>
          <div class="actions">
            <Button class="button" onClick={() => props.onNewNotebook()}>
              <Plus size={16} /> New Notebook
            </Button>
            <Button class="button primary" onClick={() => props.onNewNote(props.selected)}>
              <Plus size={16} /> New Note
            </Button>
          </div>
        </header>
        <Switch>
          <Match when={props.section === "library"}>
            <FolderView {...view} />
          </Match>
          <Match when={props.section === "search"}>
            <NoteTable view={view} title="Search results" notes={notes()} search />
          </Match>
          <Match when={props.section === "recent"}>
            <NoteTable view={view} title="Recent notes" notes={[...notes()].sort(compareBy("modified"))} />
          </Match>
          <Match when={props.section === "favorites"}>
            <NoteTable view={view} title="Favorite notes" notes={notes().filter((n) => meta(n)?.favorite)} />
          </Match>
          <Match when={props.section === "trash"}>
            <NoteTable view={view} title="Trashed notes" notes={props.trash} />
          </Match>
          <Match when={props.section === "settings"}>
            <section class="settings">
              <h2>Notes folder</h2>
              <p class="lede">{props.root.name}</p>
              <Connect onChooseFolder={props.onChooseFolder} onConnectWebDav={props.onConnectWebDav} />
            </section>
          </Match>
          <Match when={tag()}>
            <NoteTable view={view} title={`Notes tagged ${tag()}`} notes={notes().filter((n) => meta(n)?.tags.includes(tag()))} />
          </Match>
        </Switch>
      </main>
      <Show when={props.section === "library"}>
        <DetailPane {...view} />
      </Show>
      <Show when={action()} keyed>
        {(a) => <EntryDialog action={a} view={view} onClose={() => setAction(undefined)} />}
      </Show>
    </div>
  );
}
