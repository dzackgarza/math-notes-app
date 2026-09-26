// The New Notebook and New Note screens of docs/specs/tablet-ui.md. A mockup
// notebook is a folder; a mockup note is a FORMAT.md notebook directory.
import { Button } from "@kobalte/core/button";
import { RadioGroup } from "@kobalte/core/radio-group";
import { Select } from "@kobalte/core/select";
import { TextField } from "@kobalte/core/text-field";
import { Check, ChevronDown, ChevronLeft, Folder as FolderIcon, Plus } from "lucide-solid";
import { createMemo, createSignal, For, Show } from "solid-js";

import { type Folder, MY_NOTES, pathKey } from "../storage/library.ts";
import type { Store } from "../storage/store.ts";
import { noteCount, Sidebar, type SidebarProps } from "./Library.tsx";
import { PaperTile, paperLabel } from "./paper.tsx";

function FolderSelect(props: { label: string; folders: Folder[]; value: string[]; onChange: (path: string[]) => void }) {
  const selected = () => props.folders.find((f) => pathKey(f.path) === pathKey(props.value)) ?? props.folders[0];
  return (
    <Select<Folder>
      class="field"
      options={props.folders}
      // "/" keeps the top level's key non-empty: Kobalte treats "" as no selection.
      optionValue={(f) => `/${pathKey(f.path)}`}
      optionTextValue="name"
      value={selected()}
      onChange={(f) => f && props.onChange(f.path)}
      itemComponent={(item) => (
        <Select.Item item={item.item} class="menu-item">
          <Select.ItemLabel>{item.item.rawValue.name}</Select.ItemLabel>
          <Select.ItemIndicator>
            <Check size={14} />
          </Select.ItemIndicator>
        </Select.Item>
      )}
    >
      <Select.Label class="field-label">{props.label}</Select.Label>
      <Select.Trigger class="input select-trigger">
        <FolderIcon size={16} />
        <Select.Value<Folder>>{(state) => state.selectedOption().name}</Select.Value>
        <ChevronDown size={16} />
      </Select.Trigger>
      <Select.Portal>
        <Select.Content class="menu">
          <Select.Listbox />
        </Select.Content>
      </Select.Portal>
    </Select>
  );
}

export function NewNotebook(
  props: SidebarProps & { parent: string[]; onCancel: () => void; onCreate: (parent: string[], title: string) => void },
) {
  const [title, setTitle] = createSignal("");
  const [parent, setParent] = createSignal<string[]>(props.parent);
  const locations = createMemo((): Folder[] => props.folders.map((f) => (f.path.length === 0 ? { ...f, name: `${MY_NOTES} (top level)` } : f)));
  const create = () => title().trim() && props.onCreate(parent(), title().trim());
  return (
    <div class="library">
      <Sidebar {...props} />
      <main class="main form-screen">
        <div class="form-bar">
          <Button class="link-button" onClick={() => props.onCancel()}>
            <ChevronLeft size={18} /> Cancel
          </Button>
          <Button class="button primary" disabled={!title().trim()} onClick={create}>
            <Plus size={16} /> Create Notebook
          </Button>
        </div>
        <div class="form-columns">
          <form
            class="form"
            onSubmit={(e) => {
              e.preventDefault();
              create();
            }}
          >
            <h1>New Notebook</h1>
            <p class="lede">Create a new notebook to organize your notes.</p>
            <TextField value={title()} onChange={setTitle} class="field">
              <TextField.Label class="field-label">Notebook Title</TextField.Label>
              <TextField.Input class="input" autofocus />
            </TextField>
            <FolderSelect label="Location" folders={locations()} value={parent()} onChange={setParent} />
            <p class="hint">You can move this notebook later.</p>
          </form>
          <aside class="preview-pane">
            <h2 class="pane-heading">Preview</h2>
            <div class="cover">
              <span class="cover-title">{title().trim() || "Untitled"}</span>
            </div>
            <h3 class="pane-heading">Notebook Details</h3>
            <ul class="details">
              <li>
                <FolderIcon size={16} /> {locations().find((f) => pathKey(f.path) === pathKey(parent()))?.name}
              </li>
            </ul>
          </aside>
        </div>
      </main>
    </div>
  );
}

export function NewNote(props: {
  root: Store;
  folders: Folder[];
  templates: string[];
  folder: string[];
  onCancel: () => void;
  onCreate: (folder: string[], title: string, template: string) => void;
}) {
  const [title, setTitle] = createSignal("");
  const [folder, setFolder] = createSignal(props.folder);
  const [template, setTemplate] = createSignal(props.templates.includes("dotted") ? "dotted" : props.templates[0]);
  const target = () => props.folders.find((f) => pathKey(f.path) === pathKey(folder())) ?? props.folders[0];
  const create = () => title().trim() && props.onCreate(target().path, title().trim(), template());
  return (
    <main class="new-note">
      <div class="form-bar">
        <Button class="link-button" onClick={() => props.onCancel()}>
          <ChevronLeft size={18} /> Cancel
        </Button>
        <div class="target">
          <Show when={target().notes[0]} fallback={<div class="paper-tile target-thumb empty-cover" />}>
            {(first) => <PaperTile root={props.root} template={first().template} class="target-thumb" />}
          </Show>
          <div>
            <div class="target-name">{target().name}</div>
            <div class="card-meta">{noteCount(target().notes.length)}</div>
          </div>
        </div>
      </div>
      <div class="form-columns">
        <form
          class="form"
          onSubmit={(e) => {
            e.preventDefault();
            create();
          }}
        >
          <h1>New Note</h1>
          <p class="subtitle">in {target().name}</p>
          <TextField value={title()} onChange={setTitle} class="field">
            <TextField.Label class="field-label">Title</TextField.Label>
            <TextField.Input class="input" autofocus />
          </TextField>
          <RadioGroup value={template()} onChange={setTemplate} class="field">
            <RadioGroup.Label class="field-label">Paper Style</RadioGroup.Label>
            <div class="paper-options">
              <For each={props.templates}>
                {(name) => (
                  <RadioGroup.Item value={name} class="paper-option">
                    <RadioGroup.ItemInput class="sr-only" />
                    <RadioGroup.ItemControl class="paper-control">
                      <PaperTile root={props.root} template={name} class="option-tile" />
                    </RadioGroup.ItemControl>
                    <RadioGroup.ItemLabel class="option-label">{paperLabel(name)}</RadioGroup.ItemLabel>
                  </RadioGroup.Item>
                )}
              </For>
            </div>
          </RadioGroup>
          <FolderSelect label="Notebook" folders={props.folders} value={target().path} onChange={setFolder} />
        </form>
        <div class="page-preview" aria-label="Page preview">
          <PaperTile root={props.root} template={template()} class="preview-tile" />
          <span class="preview-title">{title()}</span>
        </div>
      </div>
      <div class="form-footer">
        <Button class="button primary" disabled={!title().trim()} onClick={create}>
          <Plus size={16} /> Create Note
        </Button>
      </div>
    </main>
  );
}
