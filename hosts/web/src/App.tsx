import { IonApp, IonButton, IonCard, IonCardContent, IonContent, IonIcon, IonText } from "@ionic-solidjs/core";
import { folderOpenOutline } from "ionicons/icons";
import { createEffect, createResource, createSignal, Match, onCleanup, onMount, Show, Switch } from "solid-js";

import { Editor, type Tab } from "./editor/Editor.tsx";
import { createNotebook, openNotebook, type OpenNotebook } from "./editor/notebook.ts";
import type { Engine } from "./engine/engine.ts";
import { loadEngine } from "./engine/load.ts";
import { ensureTemplates, hasPermission, listTemplates, pickRoot, requestPermission, savedRoot } from "./storage/folder.ts";
import { createFolder, moveEntry, moveToTrash, MY_NOTES, type Note, pathKey, scanLibrary, scanTrash } from "./storage/library.ts";
import { emptyNote, type LibraryMetadata, moveNotes, readMetadata, writeMetadata } from "./storage/metadata.ts";
import { noteThumbnail, thumbnailStats } from "./storage/thumbnails.ts";
import { NewNote, NewNotebook } from "./ui/Create.tsx";
import { presentModal, toast } from "./ui/ionic.ts";
import { addTagPrompt, AppMark, Library, LibraryHeader, type Section, Shell } from "./ui/Library.tsx";

// `?root=opfs` uses the origin-private file system as the notes folder: the
// automated tests cannot drive the native folder picker.
async function initialRoot(): Promise<{ root?: FileSystemDirectoryHandle; needsGesture: boolean }> {
  if (new URLSearchParams(location.search).get("root") === "opfs") {
    window.mathNotesWrites = [];
    window.mathNotesThumbnails = thumbnailStats;
    return { root: await navigator.storage.getDirectory(), needsGesture: false };
  }
  const root = await savedRoot();
  if (!root) return { needsGesture: false };
  return (await hasPermission(root)) ? { root, needsGesture: false } : { root, needsGesture: true };
}

// Everything the library screens show, read from the notes root.
async function readLibrary(args: { root: FileSystemDirectoryHandle; engine: Engine }) {
  await ensureTemplates(args.root, args.engine);
  const [folders, trash, metadata, templates] = await Promise.all([
    scanLibrary(args.root),
    scanTrash(args.root),
    readMetadata(args.root),
    listTemplates(args.root),
  ]);
  return { folders, trash, metadata, templates };
}

// The form sheets' size on a tablet screen (docs/specs/ui/tablet-new-*.png).
const SHEET = { cssClass: "form-sheet" };

export function App() {
  const [engine] = createResource<Engine>(loadEngine);
  const [start] = createResource(initialRoot);
  const [root, setRoot] = createSignal<FileSystemDirectoryHandle>();
  const [section, setSection] = createSignal<Section>("library");
  const [selected, setSelected] = createSignal<string[]>([]);
  const [open, setOpen] = createSignal<OpenNotebook>();
  const [tabs, setTabs] = createSignal<Tab[]>([]);

  const current = () => root() ?? (start()?.needsGesture ? undefined : start()?.root);
  const [library, { refetch, mutate }] = createResource(
    () => {
      const r = current(), e = engine();
      return r && e ? { root: r, engine: e } : undefined;
    },
    readLibrary,
  );

  const fail = (e: unknown) => void toast(e instanceof Error ? e.message : String(e), "danger");
  createEffect(() => engine.error && fail(`The engine did not load: ${String(engine.error)}`));
  const run = (action: () => Promise<void>) => action().catch(fail);
  const choose = () =>
    run(async () => {
      setRoot(await pickRoot());
    });
  const reconnect = () =>
    run(async () => {
      const saved = start()?.root;
      if (saved && (await requestPermission(saved))) setRoot(saved);
    });

  const showNotebook = (notebook: OpenNotebook) => {
    if (!tabs().some((t) => pathKey(t.path) === pathKey(notebook.path))) {
      setTabs([...tabs(), { path: notebook.path, name: notebook.name }]);
    }
    setOpen(notebook);
  };
  const openPath = (path: string[]) =>
    run(async () => {
      const r = current(), e = engine();
      if (r && e) showNotebook(await openNotebook(e, r, path));
    });
  const toLibrary = () => {
    setOpen(undefined);
    refetch();
  };
  const closeTab = (path: string[]) => {
    const rest = tabs().filter((t) => pathKey(t.path) !== pathKey(path));
    setTabs(rest);
    const active = open();
    if (active && pathKey(active.path) !== pathKey(path)) return;
    if (rest.length > 0) openPath(rest[rest.length - 1].path);
    else toLibrary();
  };

  const updateMetadata = (change: (m: LibraryMetadata) => LibraryMetadata) =>
    run(async () => {
      const r = current(), data = library();
      if (!r || !data) return;
      const metadata = change(data.metadata);
      mutate({ ...data, metadata });
      await writeMetadata(r, metadata);
    });
  // Changes made by other programs appear at the next scan: when the window
  // gets focus, and after each of the app's own writes.
  onMount(() => {
    const rescan = () => {
      if (!open() && library.state === "ready") refetch();
    };
    window.addEventListener("focus", rescan);
    onCleanup(() => window.removeEventListener("focus", rescan));
  });

  // The open folder is gone after a scan (moved by another program): the
  // library opens its nearest remaining ancestor.
  createEffect(() => {
    const folders = library()?.folders;
    if (!folders) return;
    let path = selected();
    while (path.length > 0 && !folders.some((f) => pathKey(f.path) === pathKey(path))) path = path.slice(0, -1);
    if (path.length !== selected().length) setSelected(path);
  });

  const inside = (path: readonly string[], dir: readonly string[]) =>
    path.length >= dir.length && dir.every((part, i) => path[i] === part);
  // Renames, moves or trashes the notebook or folder at `path`. Its notes
  // close first, as Write's DocumentList closes the documents it renames
  // (documentlist.cpp:576), and their metadata follows them.
  const relocate = (path: string[], move: (r: FileSystemDirectoryHandle) => Promise<string[] | null>) =>
    run(async () => {
      const r = current(), data = library();
      if (!r || !data) return;
      setTabs(tabs().filter((t) => !inside(t.path, path)));
      const to = await move(r);
      if (to) {
        const metadata = moveNotes(data.metadata, path, to);
        if (JSON.stringify(metadata) !== JSON.stringify(data.metadata)) await writeMetadata(r, metadata);
        if (inside(selected(), path)) setSelected([...to, ...selected().slice(path.length)]);
      } else if (inside(selected(), path)) {
        setSelected([]);
      }
      await refetch();
    });
  const rename = (path: string[], name: string) => relocate(path, (r) => moveEntry(r, path, path.slice(0, -1), name));
  const move = (path: string[], parent: string[]) => relocate(path, (r) => moveEntry(r, path, parent, path[path.length - 1]));
  const trash = (path: string[]) =>
    relocate(path, async (r) => {
      await moveToTrash(r, path);
      return null;
    });
  const thumbnail = (note: Note) => {
    const r = current(), e = engine();
    return r && e ? noteThumbnail(e, r, note) : Promise.resolve(null);
  };

  const folderOf = (path: string[]) => library()?.folders.find((f) => pathKey(f.path) === pathKey(path.slice(0, -1)));
  const noteTags = (path: string[]) => library()?.metadata.notes[pathKey(path)]?.tags ?? [];
  const setNoteTags = (path: string[], tags: string[]) =>
    updateMetadata((m) => ({ ...m, notes: { ...m.notes, [pathKey(path)]: { ...(m.notes[pathKey(path)] ?? emptyNote()), tags } } }));

  const newNotebook = () => {
    const r = current(), data = library();
    if (!r || !data) return;
    void presentModal(
      (dismiss) => (
        <NewNotebook
          root={r}
          folders={library()?.folders ?? data.folders}
          templates={data.templates}
          metadata={library()?.metadata ?? data.metadata}
          onMetadata={updateMetadata}
          parent={selected()}
          dismiss={dismiss}
          onCreate={(parent, title, fields) =>
            run(async () => {
              const path = await createFolder(r, parent, title);
              const latest = library();
              if (!latest) return;
              await writeMetadata(r, { ...latest.metadata, folders: { ...latest.metadata.folders, [pathKey(path)]: fields } });
              await refetch();
              setSection("library");
              setSelected(path);
            })
          }
        />
      ),
      SHEET,
    );
  };
  const newNote = (folder: string[]) => {
    const r = current(), data = library();
    if (!r || !data) return;
    void presentModal(
      (dismiss) => (
        <NewNote
          root={r}
          folders={library()?.folders ?? data.folders}
          templates={data.templates}
          folder={folder}
          metadata={library()?.metadata ?? data.metadata}
          onMetadata={updateMetadata}
          onSaveTemplate={(settings) => updateMetadata((m) => ({ ...m, startingTemplates: [...m.startingTemplates, settings] }))}
          dismiss={dismiss}
          onSettings={() => setSection("settings")}
          onSaveDraft={(draft) =>
            run(async () => {
              const latest = library();
              if (!latest) return;
              const metadata = { ...latest.metadata, draft };
              await writeMetadata(r, metadata);
              mutate({ ...latest, metadata });
              await dismiss();
            })
          }
          onCreate={(parent, title, template, tags, pageSize) =>
            run(async () => {
              const e = engine();
              if (!e) return;
              setSelected(parent);
              const notebook = await createNotebook(e, r, parent, title, template, pageSize);
              const metadata = library()?.metadata;
              if (metadata && (tags.length > 0 || metadata.draft)) {
                const key = pathKey(notebook.path);
                const notes = tags.length > 0 ? { ...metadata.notes, [key]: { ...emptyNote(), tags } } : metadata.notes;
                await writeMetadata(r, { ...metadata, notes, draft: undefined });
              }
              showNotebook(notebook);
              await refetch();
            })
          }
        />
      ),
      SHEET,
    );
  };

  return (
    <IonApp>
      <Show
        when={current() && library()}
        fallback={
          // The library's layout, empty, behind the folder choice.
          <>
            <Shell sidebar={{ folders: [], metadata: { tags: [], notes: {}, folders: {}, startingTemplates: [] }, section: "library", onSection: () => {}, onMetadata: () => {} }}>
              <IonContent class="main">
                <LibraryHeader title="Library" lede="A collection of mathematical notebooks." />
              </IonContent>
            </Shell>
            <div class="welcome">
              <IonCard class="welcome-card">
                <IonCardContent>
                  <AppMark />
                  <h1>Math Notes</h1>
                  <IonText color="medium">
                    <p>Your notes live in a folder on this device. Choose it to open the library.</p>
                  </IonText>
                  <Show when={!start.loading && !current()}>
                    <div class="welcome-actions">
                      <Show when={start()?.needsGesture}>
                        <IonButton fill="outline" onClick={reconnect}>
                          Reconnect folder
                        </IonButton>
                      </Show>
                      <IonButton onClick={choose}>
                        <IonIcon slot="start" icon={folderOpenOutline} />
                        Choose notes folder
                      </IonButton>
                    </div>
                  </Show>
                </IonCardContent>
              </IonCard>
            </div>
          </>
        }
      >
        {(_) => {
          const data = () => library.latest!;
          const r = () => current()!;
          return (
            <Switch>
              <Match when={open()} keyed>
                {(notebook) => (
                  <Editor
                    notebook={notebook}
                    folderName={folderOf(notebook.path)?.name ?? MY_NOTES}
                    folderDescription={data().metadata.folders[pathKey(notebook.path.slice(0, -1))]?.description ?? ""}
                    folderNotes={folderOf(notebook.path)?.notes.map((n) => ({ path: n.path, name: n.name })) ?? []}
                    libraryNotes={data().folders.flatMap((folder) => folder.notes.map((note) => ({ path: note.path, name: note.name, folderName: folder.name })))}
                    tabs={tabs()}
                    tags={noteTags(notebook.path)}
                    allTags={data().metadata.tags}
                    onToggleTag={(tag) => {
                      const tags = noteTags(notebook.path);
                      setNoteTags(notebook.path, tags.includes(tag) ? tags.filter((t) => t !== tag) : [...tags, tag]);
                    }}
                    onNewTag={() => addTagPrompt(data().metadata, updateMetadata, (tag) => setNoteTags(notebook.path, [...noteTags(notebook.path), tag]))}
                    onLibrary={toLibrary}
                    onSelectTab={openPath}
                    onCloseTab={closeTab}
                  />
                )}
              </Match>
              <Match when={true}>
                <Library
                  folders={data().folders}
                  metadata={data().metadata}
                  section={section()}
                  onSection={setSection}
                  onMetadata={updateMetadata}
                  root={r()}
                  trash={data().trash}
                  selected={selected()}
                  onSelect={setSelected}
                  onOpen={(note) => openPath(note.path)}
                  onNewNotebook={newNotebook}
                  onNewNote={newNote}
                  onTrash={trash}
                  onRename={rename}
                  onMove={move}
                  thumbnail={thumbnail}
                  onChooseFolder={choose}
                />
              </Match>
            </Switch>
          );
        }}
      </Show>
    </IonApp>
  );
}
