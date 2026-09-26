// Paper-style tiles: page 1 of a template notebook in Notes/.templates/, shown
// as an image. Page files are standalone SVG (docs/FORMAT.md, invariant 1), so
// the browser draws the tile from the file itself. Note covers are page 1 as
// the engine draws it, with the paper tile while it loads.
import { createMemo, createResource, onCleanup, Show } from "solid-js";

import { readTemplatePage } from "../storage/folder.ts";
import type { Store } from "../storage/store.ts";
import type { Note } from "../storage/library.ts";
import { lastThumbnail } from "../storage/thumbnails.ts";

const urls = new WeakMap<Store, Map<string, Promise<string>>>();

function templateUrl(root: Store, name: string): Promise<string> {
  let byName = urls.get(root);
  if (!byName) urls.set(root, (byName = new Map()));
  let url = byName.get(name);
  if (!url) {
    url = readTemplatePage(root, name).then((bytes) => {
      if (!bytes) throw new Error(`template ${name} has no page 1`);
      return URL.createObjectURL(new Blob([bytes], { type: "image/svg+xml" }));
    });
    byName.set(name, url);
  }
  return url;
}

export function PaperTile(props: { root: Store; template: string; class?: string }) {
  const [url] = createResource(() => [props.root, props.template] as const, ([root, name]) => templateUrl(root, name));
  return (
    <div class={`paper-tile ${props.class ?? ""}`}>
      <Show when={url()}>{(src) => <img src={src()} alt="" draggable={false} />}</Show>
    </div>
  );
}

// "dotted" → "Dot Paper", "lined-wide" → "Lined Paper, wide".
export function paperLabel(template: string): string {
  const [kind, spacing] = template.split("-");
  const names: Record<string, string> = { blank: "Plain Paper", dotted: "Dot Paper", lined: "Lined Paper", grid: "Grid Paper" };
  const name = names[kind] ?? template;
  return spacing ? `${name}, ${spacing}` : name;
}

// A note's cover: its page 1 as the engine draws it (src/storage/thumbnails.ts),
// or the paper of its template until that loads or when it has no page.
export function NoteCover(props: { root: Store; note: Note; thumbnail: Thumbnails; class?: string }) {
  const [png] = createResource(() => props.note, props.thumbnail, { initialValue: lastThumbnail(props.note) ?? null });
  const url = createMemo(() => {
    const blob = png.latest;
    if (!blob) return undefined;
    const src = URL.createObjectURL(blob);
    onCleanup(() => URL.revokeObjectURL(src));
    return src;
  });
  return (
    <Show when={url()} fallback={<PaperTile root={props.root} template={props.note.template} class={props.class} />}>
      {(src) => (
        <div class={`paper-tile ${props.class ?? ""}`}>
          <img src={src()} alt="" draggable={false} />
        </div>
      )}
    </Show>
  );
}

export type Thumbnails = (note: Note) => Promise<Blob | null>;
