// The New Notebook and New Note sheets of docs/specs/tablet-ui.md. A mockup
// notebook is a folder; a mockup note is a FORMAT.md notebook directory.
import { IonButton, IonButtons, IonCard, IonCardContent, IonChip, IonContent, IonFooter, IonHeader, IonIcon, IonInput, IonItem, IonLabel, IonList, IonNote, IonText, IonTextarea, IonToolbar } from "@ionic-solidjs/core";
import {
  add,
  bulbOutline,
  chevronBack,
  chevronDown,
  chevronForward,
  close,
  colorPaletteOutline,
  documentOutline,
  folderOutline,
  pricetagOutline,
  bookOutline,
  settingsOutline,
} from "ionicons/icons";
import { createMemo, createSignal, For, type JSX, Show } from "solid-js";

import { type Folder, MY_NOTES, pathKey } from "../storage/library.ts";
import { emptyFolder, type FolderMetadata, type LibraryMetadata, type NoteDraft, type PageSizeSetting, type StartingTemplate } from "../storage/metadata.ts";
import { presentPopover, promptText } from "./ionic.ts";
import { addTagPrompt, MenuItem, noteCount } from "./Library.tsx";
import { PaperTile, paperLabel } from "./paper.tsx";

// A button showing the chosen folder; it opens the list of folders.
function FolderButton(props: { label: string; folders: Folder[]; value: string[]; onChange: (path: string[]) => void; children: JSX.Element }) {
  return (
    <IonButton
      class={props.label === "Location" ? "field-select" : undefined}
      fill={props.label === "Location" ? "outline" : "clear"}
      color={props.label === "Location" ? "medium" : "primary"}
      size={props.label === "Location" ? undefined : "small"}
      aria-label={props.label}
      onClick={(e) =>
        void presentPopover(e, (dismiss) => (
          <IonList lines="full">
            <For each={props.folders}>
              {(f) => (
                <MenuItem
                  label={f.name}
                  icon={folderOutline}
                  checked={pathKey(f.path) === pathKey(props.value)}
                  dismiss={dismiss}
                  onSelect={() => props.onChange(f.path)}
                />
              )}
            </For>
          </IonList>
        ))
      }
    >
      {props.children}
    </IonButton>
  );
}

// A selectable tile: a paper, a cover or a template.
function Tile(props: { label: string; selected: boolean; onSelect: () => void; children: JSX.Element; class?: string }) {
  return (
    <IonCard button class={`tile ${props.class ?? ""}`} classList={{ selected: props.selected }} aria-pressed={props.selected} onClick={() => props.onSelect()}>
      {props.children}
      <div class="tile-label">{props.label}</div>
    </IonCard>
  );
}

// Paper styles as the mockups name them, by built-in template (#21).
const NOTEBOOK_PAPERS = [
  { template: "dotted", label: "Dot Paper" },
  { template: "grid", label: "Graph Paper" },
  { template: "blank", label: "Blank" },
  { template: "lined", label: "Ruled" },
];
const COVER_COLORS = ["#A9C1F5", "#C9B8F0", "#F2C3D3", "#F3C1A8", "#F3DE9E", "#B6E0C3", "#A9DDDB", "#C4CAD6", "#7D8BA6", "#2E3034"];

export function NewNotebook(props: {
  root: FileSystemDirectoryHandle;
  folders: Folder[];
  templates: string[];
  metadata: LibraryMetadata;
  onMetadata: (change: (metadata: LibraryMetadata) => LibraryMetadata) => void;
  parent: string[];
  dismiss: () => Promise<void>;
  onCreate: (parent: string[], title: string, fields: FolderMetadata) => void;
}) {
  const [title, setTitle] = createSignal("");
  const [description, setDescription] = createSignal("");
  const [paper, setPaper] = createSignal(props.templates.includes("dotted") ? "dotted" : props.templates[0]);
  const [coverColor, setCoverColor] = createSignal(COVER_COLORS[0]);
  const [coverStyle, setCoverStyle] = createSignal<FolderMetadata["coverStyle"]>("classic");
  const [tags, setTags] = createSignal<string[]>([]);
  const [parent, setParent] = createSignal<string[]>(props.parent);
  const locations = createMemo((): Folder[] => props.folders.map((f) => (f.path.length === 0 ? { ...f, name: `${MY_NOTES} (top level)` } : f)));
  const location = () => locations().find((f) => pathKey(f.path) === pathKey(parent()))?.name ?? MY_NOTES;
  const template = (kind: string) => props.templates.find((t) => t === kind || t.startsWith(`${kind}-`)) ?? props.templates[0];
  const color = (name: string) => props.metadata.tags.find((tag) => tag.name === name)?.color ?? "#8A8F98";
  const addTag = (e: Event) =>
    void presentPopover(e, (dismiss) => (
      <IonList lines="full">
        <For each={props.metadata.tags.filter((tag) => !tags().includes(tag.name))}>
          {(tag) => <MenuItem label={tag.name} dismiss={dismiss} onSelect={() => setTags([...tags(), tag.name])} />}
        </For>
        <MenuItem label="New Tag…" icon={add} dismiss={dismiss} onSelect={() => addTagPrompt(props.metadata, props.onMetadata, (name) => setTags([...tags(), name]))} />
      </IonList>
    ));
  const create = () => {
    if (!title().trim()) return;
    const name = title().trim();
    const fields: FolderMetadata = { description: description().trim(), paper: paper(), coverColor: coverColor(), coverStyle: coverStyle(), tags: tags() };
    // The screen behind changes once the sheet is gone.
    void props.dismiss().then(() => props.onCreate(parent(), name, fields));
  };
  return (
    <>
      <IonHeader>
        <IonToolbar>
          <IonButtons slot="start">
            <IonButton onClick={() => props.dismiss()}>
              <IonIcon slot="start" icon={chevronBack} />
              Cancel
            </IonButton>
          </IonButtons>
          <IonButtons slot="end">
            <IonButton fill="solid" color="primary" disabled={!title().trim()} onClick={create}>
              <IonIcon slot="start" icon={add} />
              Create Notebook
            </IonButton>
          </IonButtons>
        </IonToolbar>
      </IonHeader>
      <IonContent class="sheet">
        <div class="sheet-columns">
          <form
            class="form"
            onSubmit={(e) => {
              e.preventDefault();
              create();
            }}
          >
            <h1>New Notebook</h1>
            <IonText color="medium">
              <p class="lede">Create a new notebook to organize your ideas.</p>
            </IonText>
            <h3 class="field-heading">Notebook Title</h3>
            <IonInput
              class="field"
              aria-label="Notebook Title"
              placeholder="Untitled"
              autofocus
              value={title()}
              on:ionInput={(e) => setTitle(String(e.detail.value ?? ""))}
            />
            <h3 class="field-heading">
              Description <IonText color="medium">(optional)</IonText>
            </h3>
            <IonTextarea
              class="field"
              aria-label="Description"
              placeholder="What this notebook collects"
              rows={3}
              counter={true}
              maxlength={500}
              value={description()}
              on:ionInput={(e) => setDescription(String(e.detail.value ?? ""))}
            />
            <h3 class="field-heading">Paper Style</h3>
            <div class="tiles four">
              <For each={NOTEBOOK_PAPERS}>
                {(p) => (
                  <Tile label={p.label} selected={paper() === template(p.template)} onSelect={() => setPaper(template(p.template))}>
                    <PaperTile root={props.root} template={template(p.template)} class="tile-paper" />
                  </Tile>
                )}
              </For>
            </div>
            <h3 class="field-heading">Cover Color</h3>
            <div class="swatches" role="group" aria-label="Cover Color">
              <For each={COVER_COLORS}>
                {(color) => (
                  <IonButton
                    class="swatch"
                    classList={{ selected: coverColor() === color }}
                    shape="round"
                    aria-label={`Cover ${color}`}
                    style={{ "--background": color, "--background-hover": color }}
                    onClick={() => setCoverColor(color)}
                  />
                )}
              </For>
            </div>
            <h3 class="field-heading">Cover Style</h3>
            <div class="tiles two">
              <Tile label="Classic" class="cover-style" selected={coverStyle() === "classic"} onSelect={() => setCoverStyle("classic")}>
                <div class="cover-sample classic" />
              </Tile>
              <Tile label="Spine" class="cover-style" selected={coverStyle() === "spine"} onSelect={() => setCoverStyle("spine")}>
                <div class="cover-sample spine" />
              </Tile>
            </div>
            <h3 class="field-heading">Tags</h3>
            <div class="chips">
              <For each={tags()}>
                {(tag) => (
                  <IonChip class="tag-chip" style={{ "--chip": color(tag) }}>
                    <IonLabel>{tag}</IonLabel>
                    <IonIcon icon={close} aria-label={`Remove ${tag}`} onClick={() => setTags(tags().filter((name) => name !== tag))} />
                  </IonChip>
                )}
              </For>
              <IonChip outline role="button" aria-label="Add a tag" onClick={addTag}>
                <IonIcon icon={add} />
                <IonLabel>Add a tag…</IonLabel>
              </IonChip>
            </div>
            <h3 class="field-heading">Location</h3>
            <FolderButton label="Location" folders={locations()} value={parent()} onChange={setParent}>
              <IonIcon slot="start" icon={folderOutline} />
              <span class="field-select-text">{location()}</span>
              <IonIcon slot="end" icon={chevronDown} />
            </FolderButton>
            <IonNote class="hint">You can move this notebook later.</IonNote>
          </form>
          <aside class="preview-pane">
            <h3 class="field-heading">Preview</h3>
            <div class="cover" classList={{ spine: coverStyle() === "spine" }} style={{ "--cover": coverColor() }}>
              <span class="cover-title">{title().trim() || "Untitled"}</span>
              <span class="cover-mark">MATH NOTES</span>
            </div>
            <h3 class="field-heading">Notebook Details</h3>
            <IonList lines="none" class="details">
              <IonItem>
                <IonIcon slot="start" icon={documentOutline} />
                <IonLabel>{paperLabel(paper())}</IonLabel>
              </IonItem>
              <IonItem>
                <IonIcon slot="start" icon={colorPaletteOutline} />
                <IonLabel>{coverColor()}</IonLabel>
              </IonItem>
              <IonItem>
                <IonIcon slot="start" icon={bookOutline} />
                <IonLabel>{coverStyle() === "classic" ? "Classic Cover" : "Spine Cover"}</IonLabel>
              </IonItem>
              <IonItem>
                <IonIcon slot="start" icon={folderOutline} />
                <IonLabel>{location()}</IonLabel>
              </IonItem>
              <IonItem>
                <IonIcon slot="start" icon={pricetagOutline} />
                <IonLabel>{tags().length} tags</IonLabel>
              </IonItem>
            </IonList>
            <IonCard class="tip">
              <IonCardContent>
                <IonIcon icon={bulbOutline} color="primary" />
                <div>
                  <strong>Keep your work organized</strong>
                  <p>A well-named notebook with clear tags makes it easier to find and connect your ideas later.</p>
                </div>
              </IonCardContent>
            </IonCard>
          </aside>
        </div>
      </IonContent>
    </>
  );
}

export function NewNote(props: {
  root: FileSystemDirectoryHandle;
  folders: Folder[];
  templates: string[];
  folder: string[];
  metadata: LibraryMetadata;
  onMetadata: (change: (metadata: LibraryMetadata) => LibraryMetadata) => void;
  dismiss: () => Promise<void>;
  onSettings: () => void;
  onCreate: (folder: string[], title: string, template: string, tags: string[], pageSize: PageSizeSetting) => void;
  onSaveDraft: (draft: NoteDraft) => void;
  onSaveTemplate: (settings: StartingTemplate) => void;
}) {
  const [title, setTitle] = createSignal(props.metadata.draft?.title ?? "");
  const [folder, setFolder] = createSignal(props.metadata.draft?.folder ?? props.folder);
  const defaultPaper = (path: string[]) => props.metadata.folders[pathKey(path)]?.paper ?? emptyFolder().paper;
  const [template, setTemplate] = createSignal(props.metadata.draft?.template ?? defaultPaper(folder()));
  const [tags, setTags] = createSignal<string[]>(props.metadata.draft?.tags ?? []);
  const [pageSize, setPageSize] = createSignal<PageSizeSetting>(props.metadata.draft?.pageSize ?? "a4");
  const chooseFolder = (path: string[]) => {
    setFolder(path);
    setTemplate(defaultPaper(path));
  };
  const target = () => props.folders.find((f) => pathKey(f.path) === pathKey(folder())) ?? props.folders[0];
  const fields = (): NoteDraft => ({ folder: target().path, title: title().trim(), template: template(), tags: tags(), pageSize: pageSize() });
  const matchesTemplate = (settings: StartingTemplate) =>
    pathKey(settings.folder) === pathKey(target().path) && settings.paper === template() && settings.pageSize === pageSize() &&
    settings.tags.length === tags().length && settings.tags.every((tag) => tags().includes(tag));
  const useTemplate = (settings: StartingTemplate) => {
    setFolder(settings.folder);
    setTemplate(settings.paper);
    setPageSize(settings.pageSize);
    setTags([...settings.tags]);
  };
  const saveTemplate = () =>
    void promptText({
      header: "Save as template",
      label: "Template name",
      action: "Save",
      accept: (value) => {
        const name = value.trim();
        if (!name) return "Enter a template name.";
        if (props.metadata.startingTemplates.some((saved) => saved.name.toLocaleLowerCase() === name.toLocaleLowerCase())) return "A template with this name already exists.";
        props.onSaveTemplate({ name, folder: [...target().path], paper: template(), pageSize: pageSize(), tags: [...tags()] });
        return null;
      },
    });
  const create = () => {
    if (!title().trim()) return;
    const note = fields();
    // The editor opens once the sheet is gone.
    void props.dismiss().then(() => props.onCreate(note.folder, note.title, note.template, note.tags, pageSize()));
  };
  const color = (name: string) => props.metadata.tags.find((t) => t.name === name)?.color ?? "#8A8F98";
  const addTag = (e: Event) =>
    void presentPopover(e, (dismiss) => (
      <IonList lines="full">
        <For each={props.metadata.tags.filter((t) => !tags().includes(t.name))}>
          {(t) => <MenuItem label={t.name} dismiss={dismiss} onSelect={() => setTags([...tags(), t.name])} />}
        </For>
        <MenuItem label="New Tag…" icon={add} dismiss={dismiss} onSelect={() => addTagPrompt(props.metadata, props.onMetadata, (name) => setTags([...tags(), name]))} />
      </IonList>
    ));
  return (
    <>
      <IonHeader>
        <IonToolbar>
          <IonButtons slot="start">
            <IonButton onClick={() => props.dismiss()}>
              <IonIcon slot="start" icon={chevronBack} />
              Cancel
            </IonButton>
          </IonButtons>
          <div slot="end" class="target">
            <Show when={target().notes[0]} fallback={<div class="paper-tile target-thumb empty-cover" />}>
              {(first) => <PaperTile root={props.root} template={first().template} class="target-thumb" />}
            </Show>
            <div>
              <div class="target-name">{target().name}</div>
              <IonNote>{noteCount(target().notes.length)}</IonNote>
              <FolderButton label="Change Notebook" folders={props.folders} value={target().path} onChange={chooseFolder}>
                Change Notebook
                <IonIcon slot="end" icon={chevronForward} />
              </FolderButton>
            </div>
          </div>
        </IonToolbar>
      </IonHeader>
      <IonContent class="sheet">
        <div class="sheet-columns note">
          <form
            class="form"
            onSubmit={(e) => {
              e.preventDefault();
              create();
            }}
          >
            <h1>New Note</h1>
            <IonText color="medium">
              <p class="subtitle">in {target().name}</p>
            </IonText>
            <h3 class="field-heading">Title</h3>
            <IonInput
              class="field"
              aria-label="Title"
              placeholder="Untitled"
              autofocus
              value={title()}
              on:ionInput={(e) => setTitle(String(e.detail.value ?? ""))}
            />
            <h3 class="field-heading">Paper Style</h3>
            <div class="tiles papers" role="radiogroup" aria-label="Paper Style">
              <For each={props.templates}>
                {(name) => (
                  <Tile label={paperLabel(name)} selected={template() === name} onSelect={() => setTemplate(name)}>
                    <PaperTile root={props.root} template={name} class="tile-paper" />
                  </Tile>
                )}
              </For>
            </div>
            <h3 class="field-heading">Page Size</h3>
            <IonButton
              fill="outline"
              aria-label="Page Size"
              onClick={(e) => void presentPopover(e, (dismiss) => (
                <IonList lines="full">
                  <MenuItem label="A4" checked={pageSize() === "a4"} dismiss={dismiss} onSelect={() => setPageSize("a4")} />
                  <MenuItem label="Letter" checked={pageSize() === "letter"} dismiss={dismiss} onSelect={() => setPageSize("letter")} />
                </IonList>
              ))}
            >
              {pageSize() === "a4" ? "A4" : "Letter"}
              <IonIcon slot="end" icon={chevronDown} />
            </IonButton>
            <h3 class="field-heading">Tags</h3>
            <div class="chips">
              <For each={tags()}>
                {(tag) => (
                  <IonChip class="tag-chip" style={{ "--chip": color(tag) }}>
                    <IonLabel>{tag}</IonLabel>
                    <IonIcon icon={close} aria-label={`Remove ${tag}`} onClick={() => setTags(tags().filter((t) => t !== tag))} />
                  </IonChip>
                )}
              </For>
              <IonChip outline role="button" aria-label="Add Tag" onClick={addTag}>
                <IonIcon icon={add} />
                <IonLabel>Add Tag</IonLabel>
              </IonChip>
            </div>
            <h3 class="field-heading">Starting Template</h3>
            <div class="tiles four">
              <For each={props.metadata.startingTemplates}>
                {(settings) => (
                  <Tile label={settings.name} selected={matchesTemplate(settings)} onSelect={() => useTemplate(settings)}>
                    <div class="template-sample" />
                  </Tile>
                )}
              </For>
            </div>
            <IonButton fill="outline" aria-label="Save as template" onClick={saveTemplate}>Save as template</IonButton>
          </form>
          <div class="page-preview" aria-label="Page preview">
            <PaperTile root={props.root} template={template()} class="preview-tile" />
            <span class="preview-title">{title()}</span>
          </div>
        </div>
      </IonContent>
      <IonFooter>
        <IonToolbar>
          <IonButtons slot="start">
            <IonButton
              color="medium"
              onClick={() => {
                props.dismiss();
                props.onSettings();
              }}
            >
              <IonIcon slot="start" icon={settingsOutline} />
              Settings
            </IonButton>
          </IonButtons>
          <IonButtons slot="end">
            <IonButton class="tinted" fill="solid" onClick={() => props.onSaveDraft(fields())}>
              Save as Draft
            </IonButton>
            <IonButton fill="solid" color="primary" disabled={!title().trim()} onClick={create}>
              <IonIcon slot="start" icon={add} />
              Create Note
            </IonButton>
          </IonButtons>
        </IonToolbar>
      </IonFooter>
    </>
  );
}
