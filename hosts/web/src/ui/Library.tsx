// The library screen of docs/specs/tablet-ui.md: sidebar, folder cards with
// filter, sort and grid/list toggle, and the detail pane of the open folder.
// The sidebar's Search, Recent, Favorites and tag views are views of one
// table of notes (spec, "Relation to the current model", item 5).
import { IonButton, IonCard, IonCardContent, IonCheckbox, IonChip, IonContent, IonIcon, IonItem, IonLabel, IonList, IonListHeader, IonMenu, IonNote, IonSearchbar, IonSegment, IonSegmentButton, IonSplitPane, IonText, IonThumbnail } from "@ionic-solidjs/core";
import {
  add,
  bookOutline,
  checkmark,
  chevronBack,
  chevronDown,
  chevronForward,
  ellipsisHorizontal,
  folderOutline,
  gridOutline,
  listOutline,
  searchOutline,
  settingsOutline,
  star,
  starOutline,
  timeOutline,
  trashOutline,
} from "ionicons/icons";
import { createMemo, createSignal, For, type JSX, Match, mergeProps, Show, Switch } from "solid-js";

import { compareBy, type Folder, MY_NOTES, nameError, type Note, pathKey, type Sort } from "../storage/library.ts";
import { emptyFolder, emptyNote, type LibraryMetadata, type NoteMetadata, TAG_COLORS } from "../storage/metadata.ts";
import { chooseAction, presentPopover, promptText } from "./ionic.ts";
import { NoteCover, PaperTile, paperLabel, type Thumbnails } from "./paper.tsx";

export type Section = "library" | "search" | "recent" | "favorites" | "trash" | "settings" | `tag:${string}`;

export interface LibraryProps {
  root: FileSystemDirectoryHandle;
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

// One entry of a popover menu; choosing it closes the menu.
export function MenuItem(props: { label: string; icon?: string; checked?: boolean; danger?: boolean; dismiss: () => void; onSelect: () => void }) {
  return (
    <IonItem
      button
      detail={false}
      color={props.danger ? "danger" : undefined}
      onClick={() => {
        props.dismiss();
        props.onSelect();
      }}
    >
      <Show when={props.icon}>{(icon) => <IonIcon slot="start" icon={icon()} />}</Show>
      <IonLabel>{props.label}</IonLabel>
      <Show when={props.checked}>
        <IonIcon slot="end" color="primary" icon={checkmark} />
      </Show>
    </IonItem>
  );
}

// A button that opens a menu of choices, the current one checked.
export function ChoiceButton<T extends string>(props: {
  label: string;
  icon?: string;
  choices: { value: T; label: string }[];
  value: T;
  onChange: (value: T) => void;
  class?: string;
}) {
  return (
    <IonButton
      class={props.class ?? "choice-button"}
      fill="outline"
      color="medium"
      aria-label={props.label}
      onClick={(e) =>
        void presentPopover(e, (dismiss) => (
          <IonList lines="full">
            <For each={props.choices}>
              {(c) => <MenuItem label={c.label} checked={c.value === props.value} dismiss={dismiss} onSelect={() => props.onChange(c.value)} />}
            </For>
          </IonList>
        ))
      }
    >
      <Show when={props.icon}>{(icon) => <IonIcon slot="start" icon={icon()} />}</Show>
      {props.choices.find((c) => c.value === props.value)?.label}
      <IonIcon slot="end" icon={chevronDown} />
    </IonButton>
  );
}

export type SidebarProps = Pick<LibraryProps, "folders" | "metadata" | "section" | "onSection" | "onMetadata">;

export function addTagPrompt(metadata: LibraryMetadata, onMetadata: LibraryProps["onMetadata"], then?: (name: string) => void) {
  void promptText({
    header: "New Tag",
    label: "Name",
    action: "Add Tag",
    accept: (text) => {
      const name = text.trim();
      if (!name) return "A tag needs a name.";
      if (metadata.tags.some((t) => t.name === name)) return `There is already a tag “${name}”.`;
      onMetadata((m) => ({ ...m, tags: [...m.tags, { name, color: TAG_COLORS[m.tags.length % TAG_COLORS.length] }] }));
      then?.(name);
      return null;
    },
  });
}

export function Sidebar(props: SidebarProps) {
  const notes = () => props.folders.flatMap((f) => f.notes);
  const tagCount = (tag: string) => notes().filter((n) => props.metadata.notes[pathKey(n.path)]?.tags.includes(tag)).length;
  const item = (section: Section, icon: () => JSX.Element, label: string, count?: () => number) => (
    <IonItem
      button
      detail={false}
      class="nav-item"
      classList={{ selected: props.section === section }}
      aria-current={props.section === section ? "page" : undefined}
      onClick={() => props.onSection(section)}
    >
      {icon()}
      <IonLabel>{label}</IonLabel>
      <Show when={count}>{(c) => <IonNote slot="end">{c()()}</IonNote>}</Show>
    </IonItem>
  );
  const glyph = (icon: string) => () => <IonIcon slot="start" icon={icon} />;
  return (
    <IonContent class="sidebar">
      <nav class="sidebar-column" aria-label="Library">
        <div class="brand">
          <AppMark />
          <div class="brand-name">Math Notes</div>
          <IonNote class="brand-tagline">Ideas for a more mathematical world.</IonNote>
        </div>
        <IonList lines="none" class="nav-list">
          {item("library", glyph(bookOutline), "Library")}
          {item("search", glyph(searchOutline), "Search")}
          {item("recent", glyph(timeOutline), "Recent")}
          {item("favorites", glyph(starOutline), "Favorites")}
          {item("trash", glyph(trashOutline), "Trash")}
        </IonList>
        <IonList lines="none" class="nav-list tags">
          <IonListHeader>
            <IonLabel>Tags</IonLabel>
            <IonButton aria-label="Add tag" onClick={() => addTagPrompt(props.metadata, props.onMetadata)}>
              <IonIcon slot="icon-only" icon={add} />
            </IonButton>
          </IonListHeader>
          <For each={props.metadata.tags}>
            {(tag) =>
              item(`tag:${tag.name}`, () => <span slot="start" class="tag-dot" style={{ background: tag.color }} />, tag.name, () => tagCount(tag.name))
            }
          </For>
        </IonList>
        <div class="sidebar-spacer" />
        <IonList lines="none" class="nav-list">
          {item("settings", glyph(settingsOutline), "Settings")}
        </IonList>
      </nav>
    </IonContent>
  );
}

export function TagChips(props: { metadata: LibraryMetadata; tags: string[] }) {
  const color = (name: string) => props.metadata.tags.find((t) => t.name === name)?.color ?? "#8A8F98";
  return (
    <div class="chips">
      <For each={props.tags}>
        {(tag) => (
          <IonChip class="tag-chip" style={{ "--chip": color(tag) }}>
            <IonLabel>{tag}</IonLabel>
          </IonChip>
        )}
      </For>
    </div>
  );
}

// The library's props, with the sort order.
interface View extends LibraryProps {
  sort: Sort;
  onSort: (sort: Sort) => void;
}

// The names in folder `parent` (path segments; [] is the root) that the scan
// found: its notes and its subfolders.
function namesIn(folders: readonly Folder[], parent: readonly string[]): string[] {
  const key = pathKey(parent);
  const notes = folders.find((f) => pathKey(f.path) === key)?.notes.map((n) => n.name) ?? [];
  const subfolders = folders.filter((f) => f.path.length === parent.length + 1 && pathKey(f.path.slice(0, -1)) === key);
  return [...notes, ...subfolders.map((f) => f.path[f.path.length - 1])];
}

// Rename (a name checked as Write's NewDocDialog checks it) and move (the
// folders the entry can go to) of a notebook or folder.
function rename(view: View, path: string[], folder: boolean) {
  const name = path[path.length - 1];
  void promptText({
    header: `Rename ${folder ? "Notebook" : "Note"}`,
    label: "Name",
    value: name,
    action: "Rename",
    accept: (text) => {
      const next = text.trim();
      if (next === name) return null;
      const error = nameError(next, namesIn(view.folders, path.slice(0, -1)));
      if (error) return error;
      view.onRename(path, next);
      return null;
    },
  });
}

function move(view: View, path: string[], folder: boolean) {
  const parent = path.slice(0, -1);
  // Not the current folder, and for a folder not itself or a folder inside it.
  const targets = view.folders
    .map((f) => f.path)
    .filter((p) => pathKey(p) !== pathKey(parent))
    .filter((p) => !(folder && p.length >= path.length && path.every((part, i) => p[i] === part)))
    .sort((a, b) => (a.length === 0 ? -1 : b.length === 0 ? 1 : pathKey(a).localeCompare(pathKey(b))));
  void chooseAction(
    `Move “${path[path.length - 1]}” to`,
    targets.map((target) => ({ text: target.length === 0 ? MY_NOTES : target.join(" / "), handler: () => view.onMove(path, target) })),
  );
}

// Rename…, Move to… and Move to Trash, in a note's or a folder's ⋯ menu.
function EntryItems(props: { path: string[]; folder: boolean; view: View; dismiss: () => void }) {
  return (
    <>
      <MenuItem label="Rename…" dismiss={props.dismiss} onSelect={() => rename(props.view, props.path, props.folder)} />
      <MenuItem label="Move to…" dismiss={props.dismiss} onSelect={() => move(props.view, props.path, props.folder)} />
      <MenuItem label="Move to Trash" danger dismiss={props.dismiss} onSelect={() => props.view.onTrash(props.path)} />
    </>
  );
}

function MenuButton(props: { name: string; class?: string; menu: (dismiss: () => void) => JSX.Element }) {
  return (
    <IonButton
      class={props.class}
      fill="clear"
      color="medium"
      aria-label={`${props.name} actions`}
      onClick={(e) => {
        e.stopPropagation();
        void presentPopover(e, props.menu);
      }}
    >
      <IonIcon slot="icon-only" icon={ellipsisHorizontal} />
    </IonButton>
  );
}

// The ⋯ menu of a note: favorite, tags, rename, move, move to the trash.
function NoteMenu(props: { note: Note; view: View; class?: string }) {
  const key = () => pathKey(props.note.path);
  const meta = (): NoteMetadata => props.view.metadata.notes[key()] ?? emptyNote();
  const change = (update: (note: NoteMetadata) => NoteMetadata) =>
    props.view.onMetadata((m) => ({ ...m, notes: { ...m.notes, [key()]: update(m.notes[key()] ?? emptyNote()) } }));
  return (
    <MenuButton
      name={props.note.name}
      class={props.class}
      menu={(dismiss) => (
        <IonList lines="full">
          <IonItem>
            <IonCheckbox justify="space-between" checked={meta().favorite} on:ionChange={(e) => change((n) => ({ ...n, favorite: !!e.detail.checked }))}>
              Favorite
            </IonCheckbox>
          </IonItem>
          <For each={props.view.metadata.tags}>
            {(tag) => (
              <IonItem>
                <span slot="start" class="tag-dot" style={{ background: tag.color }} />
                <IonCheckbox
                  justify="space-between"
                  checked={meta().tags.includes(tag.name)}
                  on:ionChange={(e) =>
                    change((n) => ({ ...n, tags: e.detail.checked ? [...n.tags, tag.name] : n.tags.filter((t) => t !== tag.name) }))
                  }
                >
                  {tag.name}
                </IonCheckbox>
              </IonItem>
            )}
          </For>
          <Show when={props.note.path[0] !== ".trash"}>
            <EntryItems path={props.note.path} folder={false} view={props.view} dismiss={dismiss} />
          </Show>
        </IonList>
      )}
    />
  );
}

function NoteRow(props: { note: Note; subtitle: string; view: View }) {
  const meta = () => props.view.metadata.notes[pathKey(props.note.path)];
  return (
    <li class="note-row">
      <IonItem button detail={false} lines="none" class="note-open" onClick={() => props.view.onOpen(props.note)}>
        <IonThumbnail slot="start" class="note-thumb">
          <NoteCover root={props.view.root} note={props.note} thumbnail={props.view.thumbnail} />
        </IonThumbnail>
        <IonLabel>
          <h3 class="note-title">
            {props.note.name}
            <Show when={meta()?.favorite}>
              <IonIcon class="favorite-mark" color="warning" icon={star} aria-label="Favorite" />
            </Show>
          </h3>
          <p>{meta()?.description || props.subtitle}</p>
          <p class="note-time">{ago(props.note.modified)}</p>
        </IonLabel>
      </IonItem>
      <NoteMenu note={props.note} view={props.view} class="row-menu" />
    </li>
  );
}

// A folder's cover: its first note's page 1 (spec, "New Notebook").
function FolderCover(props: { folder: Folder; view: View; class: string }) {
  const meta = () => props.view.metadata.folders[pathKey(props.folder.path)] ?? emptyFolder();
  return (
    <div class={`folder-cover ${props.class}`} classList={{ spine: meta().coverStyle === "spine" }} style={{ "--cover": meta().coverColor }}>
      <Show when={[...props.folder.notes].sort(compareBy(props.view.sort))[0]} fallback={<PaperTile root={props.view.root} template={meta().paper} />}>
        {(first) => <NoteCover root={props.view.root} note={first()} thumbnail={props.view.thumbnail} />}
      </Show>
    </div>
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
              <IonIcon class="breadcrumb-separator" icon={chevronForward} />
            </Show>
            <IonButton
              size="small"
              fill="clear"
              color={i() === steps().length - 1 ? "dark" : "primary"}
              aria-current={i() === steps().length - 1 ? "page" : undefined}
              onClick={() => props.onSelect(path)}
            >
              {lastName(path)}
            </IonButton>
          </>
        )}
      </For>
    </nav>
  );
}

// Which notes the grid shows: all, the favorites, or one tag's.
type Filter = "all" | "favorites" | `tag:${string}`;

// The open folder as GoodNotes and Noteful show one: its subfolders, then its
// notes, in one grid. A folder opens on a tap; a note opens in the editor.
function FolderView(props: View) {
  const [query, setQuery] = createSignal("");
  const [filter, setFilter] = createSignal<Filter>("all");
  const [layout, setLayout] = createSignal<"grid" | "list">("grid");
  const matches = (name: string) => name.toLowerCase().includes(query().trim().toLowerCase());
  const noteMeta = (n: Note) => props.metadata.notes[pathKey(n.path)];
  const passes = (n: Note) => {
    const f = filter();
    if (f === "all") return true;
    if (f === "favorites") return !!noteMeta(n)?.favorite;
    return !!noteMeta(n)?.tags.includes(f.slice(4));
  };
  const folders = createMemo(() =>
    filter() === "all" ? subfolders(props.folders, props.selected).filter((f) => matches(lastName(f.path))).sort(compareBy(props.sort)) : [],
  );
  const notes = createMemo(() => {
    const here = props.folders.find((f) => pathKey(f.path) === pathKey(props.selected))?.notes ?? [];
    return here.filter((n) => matches(n.name) && passes(n)).sort(compareBy(props.sort));
  });
  const folderTags = (folder: Folder) => props.metadata.folders[pathKey(folder.path)]?.tags ?? [];
  const folderMeta = (folder: Folder) => {
    const inner = subfolders(props.folders, folder.path).length;
    return inner > 0 ? `${noteCount(folder.notes.length)} · ${inner} ${inner === 1 ? "folder" : "folders"}` : noteCount(folder.notes.length);
  };
  const filters = () => [
    { value: "all" as Filter, label: "All Notebooks" },
    { value: "favorites" as Filter, label: "Favorites" },
    ...props.metadata.tags.map((t) => ({ value: `tag:${t.name}` as Filter, label: t.name })),
  ];
  return (
    <>
      <Breadcrumb {...props} />
      <div class="filters">
        <IonSearchbar
          class="main-search"
          placeholder="Search notebooks…"
          aria-label="Search notebooks"
          value={query()}
          on:ionInput={(e) => setQuery(String(e.detail.value ?? ""))}
        />
        <ChoiceButton label="Filter" choices={filters()} value={filter()} onChange={setFilter} />
        <ChoiceButton
          label="Sort"
          choices={[
            { value: "modified", label: "Last Modified" },
            { value: "name", label: "Name" },
          ]}
          value={props.sort}
          onChange={props.onSort}
        />
        <IonSegment class="layout-toggle" value={layout()} on:ionChange={(e) => setLayout(e.detail.value === "list" ? "list" : "grid")}>
          <IonSegmentButton value="grid" aria-label="Grid">
            <IonIcon icon={gridOutline} />
          </IonSegmentButton>
          <IonSegmentButton value="list" aria-label="List">
            <IonIcon icon={listOutline} />
          </IonSegmentButton>
        </IonSegment>
      </div>
      <ul class={layout() === "grid" ? "cards" : "cards list"} aria-label="Notebooks">
        <For each={folders()}>
          {(folder) => (
            <li class="card-cell">
              <IonCard button class="card" aria-label={lastName(folder.path)} onClick={() => props.onSelect(folder.path)}>
                <FolderCover folder={folder} view={props} class="card-cover" />
                <IonCardContent class="card-text">
                  <h2 class="card-title">
                    <IonIcon class="folder-mark" color="primary" icon={folderOutline} /> {lastName(folder.path)}
                  </h2>
                  <p>{folderMeta(folder)}</p>
                  <Show when={folder.modified > 0}>
                    <p>Modified {ago(folder.modified)}</p>
                  </Show>
                  <Show when={props.metadata.folders[pathKey(folder.path)]}>
                    {(meta) => (
                      <>
                        <Show when={meta().description}><p>{meta().description}</p></Show>
                        <p>{paperLabel(meta().paper)} · {meta().coverStyle === "classic" ? "Classic" : "Spine"} cover</p>
                      </>
                    )}
                  </Show>
                  <TagChips metadata={props.metadata} tags={folderTags(folder)} />
                </IonCardContent>
              </IonCard>
              <MenuButton
                name={lastName(folder.path)}
                class="card-menu"
                menu={(dismiss) => (
                  <IonList lines="full">
                    <EntryItems path={folder.path} folder view={props} dismiss={dismiss} />
                  </IonList>
                )}
              />
            </li>
          )}
        </For>
        <For each={notes()}>
          {(note) => (
            <li class="card-cell">
              <IonCard button class="card" aria-label={note.name} onClick={() => props.onOpen(note)}>
                <NoteCover root={props.root} note={note} thumbnail={props.thumbnail} class="card-cover" />
                <IonCardContent class="card-text">
                  <h2 class="card-title">{note.name}</h2>
                  <p>Modified {ago(note.modified)}</p>
                  <TagChips metadata={props.metadata} tags={noteMeta(note)?.tags ?? []} />
                </IonCardContent>
              </IonCard>
              <NoteMenu note={note} view={props} class="card-menu" />
            </li>
          )}
        </For>
      </ul>
      <Show when={folders().length === 0 && notes().length === 0}>
        <IonText color="medium">
          <p class="empty">{query().trim() || filter() !== "all" ? "Nothing matches." : "This folder is empty."}</p>
        </IonText>
      </Show>
    </>
  );
}

function DetailPane(props: View) {
  const folder = () => props.folders.find((f) => pathKey(f.path) === pathKey(props.selected));
  const meta = () => props.metadata.folders[pathKey(props.selected)] ?? emptyFolder();
  const updateTags = (tags: string[]) =>
    props.onMetadata((m) => ({ ...m, folders: { ...m.folders, [pathKey(props.selected)]: { ...(m.folders[pathKey(props.selected)] ?? emptyFolder()), tags } } }));
  const tagMenu = (e: Event) =>
    void presentPopover(e, (dismiss) => (
      <IonList lines="full">
        <For each={props.metadata.tags}>
          {(tag) => (
            <IonItem>
              <span slot="start" class="tag-dot" style={{ background: tag.color }} />
              <IonCheckbox
                justify="space-between"
                checked={meta().tags.includes(tag.name)}
                on:ionChange={(event) => updateTags(event.detail.checked ? [...meta().tags, tag.name] : meta().tags.filter((name) => name !== tag.name))}
              >
                {tag.name}
              </IonCheckbox>
            </IonItem>
          )}
        </For>
        <MenuItem label="New Tag…" icon={add} dismiss={dismiss} onSelect={() => addTagPrompt(props.metadata, props.onMetadata, (name) => updateTags([...meta().tags, name]))} />
      </IonList>
    ));
  const [query, setQuery] = createSignal("");
  const [tab, setTab] = createSignal<"notes" | "info">("notes");
  const parent = () => props.selected.slice(0, -1);
  return (
    <Show when={folder()}>
      {(f) => (
        <aside class="detail" aria-label={`${f().name} notes`}>
          <div class="detail-bar">
            <Show when={props.selected.length > 0} fallback={<span />}>
              <IonButton fill="clear" size="small" onClick={() => props.onSelect(parent())}>
                <IonIcon slot="start" icon={chevronBack} />
                {parent().length === 0 ? "Library" : lastName(parent())}
              </IonButton>
              <MenuButton
                name={lastName(f().path)}
                menu={(dismiss) => (
                  <IonList lines="full">
                    <EntryItems path={f().path} folder view={props} dismiss={dismiss} />
                  </IonList>
                )}
              />
            </Show>
          </div>
          <FolderCover folder={f()} view={props} class="detail-cover" />
          <h2 class="detail-title">{lastName(f().path)}</h2>
          <IonNote class="detail-meta">
            {noteCount(f().notes.length)}
            <Show when={f().modified > 0}> · Modified {ago(f().modified)}</Show>
          </IonNote>
          <Show when={meta().description}><p class="detail-description">{meta().description}</p></Show>
          <div class="chips">
            <TagChips metadata={props.metadata} tags={meta().tags} />
            <IonButton class="chip-add" size="small" fill="outline" color="medium" aria-label="Add notebook tag" onClick={tagMenu}>
              <IonIcon slot="icon-only" icon={add} />
            </IonButton>
          </div>
          <IonSegment value={tab()} on:ionChange={(e) => setTab(e.detail.value === "info" ? "info" : "notes")}>
            <IonSegmentButton value="notes">
              <IonLabel>Notes</IonLabel>
            </IonSegmentButton>
            <IonSegmentButton value="info">
              <IonLabel>Info</IonLabel>
            </IonSegmentButton>
          </IonSegment>
          <Show
            when={tab() === "notes"}
            fallback={
              <IonList lines="full" class="info-list">
                <IonItem>
                  <IonLabel>Location</IonLabel>
                  <IonNote slot="end">{[MY_NOTES, ...f().path].join(" / ")}</IonNote>
                </IonItem>
                <IonItem>
                  <IonLabel>Paper</IonLabel>
                  <IonNote slot="end">{paperLabel(meta().paper)}</IonNote>
                </IonItem>
                <IonItem>
                  <IonLabel>Cover</IonLabel>
                  <IonNote slot="end">{meta().coverStyle === "classic" ? "Classic" : "Spine"} · {meta().coverColor}</IonNote>
                </IonItem>
                <IonItem>
                  <IonLabel>Notes</IonLabel>
                  <IonNote slot="end">{f().notes.length}</IonNote>
                </IonItem>
                <IonItem>
                  <IonLabel>Folders</IonLabel>
                  <IonNote slot="end">{subfolders(props.folders, f().path).length}</IonNote>
                </IonItem>
                <IonItem>
                  <IonLabel>Modified</IonLabel>
                  <IonNote slot="end">{f().modified > 0 ? ago(f().modified) : "—"}</IonNote>
                </IonItem>
              </IonList>
            }
          >
            <IonSearchbar placeholder="Search notes…" aria-label="Search notes" value={query()} on:ionInput={(e) => setQuery(String(e.detail.value ?? ""))} />
            <ul class="note-list" aria-label="Notes">
              <For each={f().notes.filter((n) => n.name.toLowerCase().includes(query().trim().toLowerCase())).sort(compareBy(props.sort))}>
                {(note) => <NoteRow note={note} subtitle={f().name} view={props} />}
              </For>
            </ul>
          </Show>
          <IonButton class="new-in tinted" expand="block" onClick={() => props.onNewNote(f().path)}>
            <IonIcon slot="start" icon={add} />
            New Note in {lastName(f().path)}
          </IonButton>
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
        <IonSearchbar
          placeholder="Search notes by title…"
          aria-label="Search notes by title"
          value={query()}
          on:ionInput={(e) => setQuery(String(e.detail.value ?? ""))}
        />
      </Show>
      <ul class="note-list table" aria-label={props.title}>
        <For each={shown()} fallback={<li class="empty">No notes.</li>}>
          {(note) => <NoteRow note={note} subtitle={folderName(note)} view={props.view} />}
        </For>
      </ul>
    </>
  );
}

// The sidebar beside the main pane, as a split pane (docs/specs/tablet-ui.md,
// Library: the sidebar is always visible).
export function Shell(props: { sidebar: SidebarProps; children: JSX.Element }) {
  return (
    <IonSplitPane contentId="library-main" when={true}>
      <IonMenu contentId="library-main" type="overlay" class="sidebar-menu">
        <Sidebar {...props.sidebar} />
      </IonMenu>
      <div class="ion-page library-main" id="library-main">
        {props.children}
      </div>
    </IonSplitPane>
  );
}

export function LibraryHeader(props: { title: string; lede?: string; actions?: JSX.Element }) {
  return (
    <header class="main-header">
      <div>
        <h1>{props.title}</h1>
        <Show when={props.lede}>
          <IonText color="medium">
            <p class="lede">{props.lede}</p>
          </IonText>
        </Show>
      </div>
      <div class="actions">{props.actions}</div>
    </header>
  );
}

export function Library(props: LibraryProps) {
  const [sort, setSort] = createSignal<Sort>("modified");
  const view: View = mergeProps(props, {
    get sort() {
      return sort();
    },
    onSort: setSort,
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
    <Shell sidebar={props}>
      <div class={props.section === "library" ? "library-columns" : "library-columns single"}>
        <IonContent class="main">
          <LibraryHeader
            title={title()}
            lede={props.section === "library" ? "A collection of mathematical notebooks." : undefined}
            actions={
              <>
                <IonButton fill="outline" onClick={() => props.onNewNotebook()}>
                  <IonIcon slot="start" icon={add} />
                  New Notebook
                </IonButton>
                <IonButton onClick={() => props.onNewNote(props.selected)}>
                  <IonIcon slot="start" icon={add} />
                  New Note
                </IonButton>
              </>
            }
          />
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
              <IonList inset lines="full" class="settings">
                <IonItem>
                  <IonLabel>Notes folder</IonLabel>
                  <IonNote slot="end">{props.root.name || MY_NOTES}</IonNote>
                </IonItem>
                <IonItem button detail onClick={() => props.onChooseFolder()}>
                  <IonIcon slot="start" color="primary" icon={folderOutline} />
                  <IonLabel color="primary">Choose notes folder</IonLabel>
                </IonItem>
              </IonList>
            </Match>
            <Match when={tag()}>
              <NoteTable view={view} title={`Notes tagged ${tag()}`} notes={notes().filter((n) => meta(n)?.tags.includes(tag()))} />
            </Match>
          </Switch>
        </IonContent>
        <Show when={props.section === "library"}>
          <IonContent class="detail-pane">
            <DetailPane {...view} />
          </IonContent>
        </Show>
      </div>
    </Shell>
  );
}
