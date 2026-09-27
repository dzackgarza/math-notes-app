import { IonButton, IonButtons, IonCheckbox, IonChip, IonContent, IonHeader, IonIcon, IonInput, IonItem, IonLabel, IonList, IonListHeader, IonNote, IonRange, IonSearchbar, IonTextarea, IonToolbar } from "@ionic-solidjs/core";
import {
  add,
  arrowRedo,
  arrowUndo,
  checkmark,
  chevronBack,
  chevronDown,
  chevronForward,
  close,
  copyOutline,
  cutOutline,
  duplicateOutline,
  ellipsisHorizontal,
  gridOutline,
  shareOutline,
  trashOutline,
} from "ionicons/icons";
import {
  Brush as BrushIcon,
  DraftingCompass,
  Eraser as EraserIcon,
  Highlighter,
  Image as ImageIcon,
  Lasso,
  PenLine,
  Type as TextIcon,
} from "lucide-solid";
import { For, type JSX, Show, createEffect, createResource, createSignal, onCleanup, onMount } from "solid-js";
import { deserializeScene, sceneBounds, type Geometry, type Scene } from "@dzackgarza/freetikz/scene";
import { generateTikz } from "@dzackgarza/freetikz/tikz";

import { Brush, Eraser, PageSize, Selector, type Canvas, type Pen, type SelectionInfo, type ToolSettings } from "../engine/engine.ts";
import { ViewController, type View } from "../input/gestures.ts";
import { capabilities, penSamples } from "../input/pointer.ts";
import { listTemplates } from "../storage/folder.ts";
import type { Tag } from "../storage/metadata.ts";
import { readPens, writePens } from "../storage/pens.ts";
import { presentModal, presentPopover, toast } from "../ui/ionic.ts";
import { AppMark, MenuItem, noteCount } from "../ui/Library.tsx";
import { paperLabel } from "../ui/paper.tsx";
import { applyTemplate, type OpenNotebook } from "./notebook.ts";

// How far past the last page, in CSS px, a pull must go to add a page.
const PULL_THRESHOLD = 96;
const WHEEL_RELEASE_MS = 250;
const utf8 = new TextDecoder();

// The pen editor's brush list: the stock brushes of a pen set, as in Google
// Cahier DrawingToolbox.kt:483-505 (android/cahier 209db71). A highlighter
// draws at the default highlighter preset's opacity, the others opaque.
const BRUSHES = [
  { label: "Pen", brush: Brush.pressurePen, opacity: 1 },
  { label: "Marker", brush: Brush.marker, opacity: 1 },
  { label: "Highlighter", brush: Brush.highlighter, opacity: 0.35 },
] as const;
const SIZE_RANGE = { min: 0.2, max: 20, step: 0.1 }; // pt
// A preset edit is written to .pens.json once edits pause this long (a size drag).
const PEN_WRITE_MS = 300;

const penIcon = (brush: number, color: string) =>
  brush === Brush.highlighter ? (
    <Highlighter size={22} color={color} />
  ) : brush === Brush.marker ? (
    <BrushIcon size={22} color={color} />
  ) : (
    <PenLine size={22} color={color} />
  );

// A pen preset's id, or one of the other tools.
type ToolId = string;
const ERASER = "eraser", SELECT = "select", TEXT = "text";

// The eraser's two kinds (#23); the pen's eraser end uses the selected one.
const ERASERS = { stroke: { label: "Whole stroke", kind: Eraser.stroke }, free: { label: "Partial", kind: Eraser.free } } as const;
type EraserId = keyof typeof ERASERS;

// The selection tool's two kinds (#24).
const SELECTORS = { lasso: { label: "Freeform", kind: Selector.lasso }, rect: { label: "Rectangle", kind: Selector.rect } } as const;
type SelectorId = keyof typeof SELECTORS;

// The 15 swatches of the mockup's palette, three per row.
export const PALETTE = [
  0x1a1a1a, 0x8a8f98, 0xffffff, 0x1f4fd1, 0xd6455d, 0xf08a24, 0x3fa35b, 0x8b5cf6, 0xf5a3c7, 0xf5d547, 0x2bb3c0, 0xd8b4fe,
  0x7fb2f0, 0x8b5a2b, 0x1f3a93,
];
const hex = (rgb: number) => `#${rgb.toString(16).padStart(6, "0").toUpperCase()}`;
// A size in pt as .pens.json writes it: at most 2 decimals.
const sizeLabel = (size: number) => String(Math.round(size * 100) / 100);

function geometryPreview(geometry: Geometry): JSX.Element {
  switch (geometry.kind) {
    case "rawStroke":
      return <polyline points={geometry.points.map((p) => `${p.x},${p.y}`).join(" ")} fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" />;
    case "point":
      return <circle cx={geometry.x} cy={geometry.y} r="2" fill="currentColor" />;
    case "segment":
      return <line x1={geometry.start.x} y1={geometry.start.y} x2={geometry.end.x} y2={geometry.end.y} stroke="currentColor" stroke-width="1.5" />;
    case "circle":
      return <circle cx={geometry.center.x} cy={geometry.center.y} r={geometry.radius} fill="none" stroke="currentColor" stroke-width="1.5" />;
    case "label":
      return <text x={geometry.position.x} y={geometry.position.y} fill="currentColor" font-size="10">{geometry.tex}</text>;
  }
}

function FigurePreview(props: { scene: Scene }) {
  const frame = () => {
    const bounds = sceneBounds(props.scene);
    if (!bounds) return "0 0 100 60";
    const width = Math.max(20, bounds.maxX - bounds.minX);
    const height = Math.max(20, bounds.maxY - bounds.minY);
    const pad = 12;
    return `${bounds.minX - pad} ${bounds.minY - pad} ${width + 2 * pad} ${height + 2 * pad}`;
  };
  return (
    <svg class="figure-preview-svg" viewBox={frame()} role="img" aria-label="Drawing scene preview">
      <For each={props.scene.objects}>{(item) => geometryPreview(item.geometry)}</For>
    </svg>
  );
}

function Swatches(props: { value: number | undefined; onChange: (rgb: number) => void; children?: JSX.Element }) {
  return (
    <div class="palette" role="group" aria-label="Colors">
      <For each={PALETTE}>
        {(rgb) => (
          <IonButton
            class="swatch"
            classList={{ selected: props.value === rgb }}
            shape="round"
            aria-label={hex(rgb)}
            aria-pressed={props.value === rgb}
            style={{ "--background": hex(rgb), "--background-hover": hex(rgb) }}
            onClick={() => props.onChange(rgb)}
          />
        )}
      </For>
      {props.children}
    </div>
  );
}

// An entry of the tool rail: a tool with its name and its setting below.
function ToolItem(props: { label: string; detail?: string; selected: boolean; icon: JSX.Element; onSelect: (e: Event) => void }) {
  return (
    <IonItem
      button
      detail={false}
      lines="none"
      class="tool"
      classList={{ selected: props.selected }}
      aria-label={props.label}
      aria-pressed={props.selected}
      onClick={(e) => props.onSelect(e)}
    >
      <span slot="start" class="tool-icon">
        {props.icon}
      </span>
      <IonLabel>
        {props.label}
        <Show when={props.detail}>
          <p class="tool-size">{props.detail}</p>
        </Show>
      </IonLabel>
    </IonItem>
  );
}

// The fields of Write's pen editor that the stock brushes use: pen tip,
// color, width (PenToolbar::setPen, updateColor, updateWidth,
// syncscribble/pentoolbar.cpp:474-527, styluslabs/Write 401b65d).
function PenEditor(props: { pen: Pen; onChange: (change: Partial<ToolSettings>) => void }) {
  return (
    <div class="pen-editor" aria-label="Pen editor">
      <IonListHeader>
        <IonLabel>{props.pen.name}</IonLabel>
      </IonListHeader>
      <IonList lines="full">
        <For each={BRUSHES}>
          {(b) => (
            <IonItem button detail={false} aria-label={b.label} onClick={() => props.onChange({ brush: b.brush, opacity: b.opacity })}>
              <span slot="start" class="tool-icon">
                {penIcon(b.brush, "currentColor")}
              </span>
              <IonLabel>{b.label}</IonLabel>
              <Show when={props.pen.tool.brush === b.brush}>
                <IonIcon slot="end" color="primary" icon={checkmark} aria-hidden="true" />
              </Show>
            </IonItem>
          )}
        </For>
      </IonList>
      <Swatches value={props.pen.tool.rgb} onChange={(rgb) => props.onChange({ rgb })} />
      <IonList lines="none">
        <IonItem>
          <IonInput
            label="Hex"
            value={hex(props.pen.tool.rgb)}
            on:ionChange={(e) => {
              const v = String(e.detail.value ?? "");
              if (/^#?[0-9a-f]{6}$/i.test(v)) props.onChange({ rgb: parseInt(v.replace("#", ""), 16) });
            }}
          />
        </IonItem>
        <IonItem>
          <IonRange
            aria-label="Size"
            min={SIZE_RANGE.min}
            max={SIZE_RANGE.max}
            step={SIZE_RANGE.step}
            value={props.pen.tool.size}
            on:ionInput={(e) => props.onChange({ size: Number(e.detail.value) })}
          >
            <IonLabel slot="start">Size</IonLabel>
            <IonNote slot="end" class="tool-size">
              {sizeLabel(props.pen.tool.size)} pt
            </IonNote>
          </IonRange>
        </IonItem>
      </IonList>
    </div>
  );
}

// A bottom-bar menu button: its label, and a popover of choices.
function BarMenu(props: { label: string; icon?: string; text: string; items: (dismiss: () => void) => JSX.Element }) {
  return (
    <IonButton
      class="bar-group bar-menu"
      fill="clear"
      color="dark"
      size="small"
      aria-label={props.label}
      onClick={(e) =>
        void presentPopover(e, (dismiss) => <IonList lines="full">{props.items(dismiss)}</IonList>, { side: "top", alignment: "start" })
      }
    >
      <Show when={props.icon}>{(icon) => <IonIcon slot="start" icon={icon()} />}</Show>
      {props.text}
      <IonIcon slot="end" icon={chevronDown} />
    </IonButton>
  );
}

// Zoom factors relative to the page filling the canvas width (100%).
const ZOOMS = [0.5, 0.75, 1, 1.25, 1.5, 2, 3];

export interface Tab {
  path: string[];
  name: string;
}

export interface LibraryTab extends Tab {
  folderName: string;
}

function NotePicker(props: { notes: LibraryTab[]; dismiss: () => Promise<void>; onOpen: (path: string[]) => void }) {
  const [query, setQuery] = createSignal("");
  const shown = () => props.notes.filter((note) => `${note.name} ${note.folderName}`.toLocaleLowerCase().includes(query().trim().toLocaleLowerCase()));
  const select = (path: string[]) => void props.dismiss().then(() => props.onOpen(path));
  return (
    <>
      <IonHeader>
        <IonToolbar>
          <IonButtons slot="start">
            <IonButton onClick={() => void props.dismiss()}>Cancel</IonButton>
          </IonButtons>
        </IonToolbar>
      </IonHeader>
      <IonContent class="sheet">
        <h1>Open Note</h1>
        <IonSearchbar
          placeholder="Search notes…"
          aria-label="Search library notes"
          value={query()}
          on:ionInput={(e) => setQuery(String(e.detail.value ?? ""))}
        />
        <IonList lines="full" aria-label="Library notes">
          <For each={shown()} fallback={<IonItem><IonLabel>No notes found.</IonLabel></IonItem>}>
            {(note) => (
              <IonItem button detail={false} onClick={() => select(note.path)}>
                <IonLabel>
                  <h2>{note.name}</h2>
                  <p>{note.folderName}</p>
                </IonLabel>
              </IonItem>
            )}
          </For>
        </IonList>
      </IonContent>
    </>
  );
}

function TextSheet(props: { initial: string; dismiss: () => Promise<void>; onSave: (value: string) => void }) {
  const [value, setValue] = createSignal(props.initial);
  const save = () => void props.dismiss().then(() => props.onSave(value()));
  return (
    <>
      <IonHeader>
        <IonToolbar>
          <IonButtons slot="start"><IonButton onClick={() => void props.dismiss()}>Cancel</IonButton></IonButtons>
          <IonButtons slot="end"><IonButton disabled={!value().trim()} onClick={save}>Save Text</IonButton></IonButtons>
        </IonToolbar>
      </IonHeader>
      <IonContent class="sheet">
        <h1>Text</h1>
        <IonTextarea aria-label="Page text" value={value()} rows={6} autofocus on:ionInput={(e) => setValue(String(e.detail.value ?? ""))} />
      </IonContent>
    </>
  );
}

function PdfExportSheet(props: { pages: number; dismiss: () => Promise<void>; onExport: (first: number, count: number) => void }) {
  const [from, setFrom] = createSignal(1);
  const [through, setThrough] = createSignal(props.pages);
  const valid = () => Number.isInteger(from()) && Number.isInteger(through()) && from() >= 1 && from() <= through() && through() <= props.pages;
  const save = () => {
    if (!valid()) return;
    props.onExport(from() - 1, through() - from() + 1);
    void props.dismiss();
  };
  return (
    <>
      <IonHeader>
        <IonToolbar>
          <IonButtons slot="start"><IonButton onClick={() => void props.dismiss()}>Cancel</IonButton></IonButtons>
          <IonButtons slot="end"><IonButton disabled={!valid()} onClick={save}>Export PDF</IonButton></IonButtons>
        </IonToolbar>
      </IonHeader>
      <IonContent class="sheet">
        <h1>Export PDF</h1>
        <p>Choose pages from this note. The PDF keeps each page's size, paper, and ink.</p>
        <IonInput label="From page" labelPlacement="stacked" aria-label="From page" type="number" min="1" max={props.pages} value={from()} on:ionInput={(e) => setFrom(Number(e.detail.value))} />
        <IonInput label="Through page" labelPlacement="stacked" aria-label="Through page" type="number" min="1" max={props.pages} value={through()} on:ionInput={(e) => setThrough(Number(e.detail.value))} />
        <Show when={!valid()}><IonNote color="danger">Choose pages from 1 to {props.pages}.</IonNote></Show>
      </IonContent>
    </>
  );
}

export function Editor(props: {
  notebook: OpenNotebook;
  folderName: string;
  folderDescription: string;
  // The notes of the open note's folder, for the title menu.
  folderNotes: Tab[];
  libraryNotes: LibraryTab[];
  tabs: Tab[];
  // The note's tags, and the library's tags to add.
  tags: string[];
  allTags: Tag[];
  onToggleTag: (tag: string) => void;
  onNewTag: () => void;
  // Each runs after the editor saved and freed the open notebook.
  onLibrary: () => void;
  onSelectTab: (path: string[]) => void;
  onCloseTab: (path: string[]) => void;
}) {
  let area!: HTMLDivElement;
  let element!: HTMLCanvasElement;
  let imageInput!: HTMLInputElement;
  let canvas: Canvas | undefined;
  let frame = 0;
  const ids = { next: 0 };
  const { document: doc, saver, root } = props.notebook;
  const [templates] = createResource(() => listTemplates(root));
  const [template, setTemplate] = createSignal(props.notebook.template);
  // The presets of Notes/.pens.json, in toolbar order.
  const [pens, setPens] = createSignal<Pen[]>([]);
  const [tool, setTool] = createSignal<ToolId>("");
  // The preset the palette and the pen editor change: the selected pen, or
  // the last one before the eraser or the lasso.
  const [penId, setPenId] = createSignal("");
  const pen = () => pens().find((p) => p.id === penId());
  const [eraser, setEraser] = createSignal<EraserId>("stroke");
  const [selector, setSelector] = createSignal<SelectorId>("lasso");
  const [selection, setSelection] = createSignal<SelectionInfo | null>(null);
  const [drawing, setDrawing] = createSignal(false);
  const [figureScene, setFigureScene] = createSignal<Scene | null>(null);
  const [figureTikz, setFigureTikz] = createSignal("");
  const [figureId, setFigureId] = createSignal("");
  const [figurePanel, setFigurePanel] = createSignal(false);
  const [figurePage, setFigurePage] = createSignal(0);
  const [figureOverlay, setFigureOverlay] = createSignal(false);
  const selectTool = (id: ToolId) => {
    setTool(id);
    if (id !== ERASER && id !== SELECT && id !== TEXT) setPenId(id);
  };

  // A pen edit applies at once (Write PenToolbar::updateColor, updateWidth,
  // syncscribble/pentoolbar.cpp:506-527, styluslabs/Write 401b65d); the file
  // is written when the edits pause.
  let penWrite = 0;
  let penWritePending: Promise<void> | undefined;
  const writePensNow = () => {
    clearTimeout(penWrite);
    penWrite = 0;
    penWritePending = writePens(root, doc.engine, pens());
    return penWritePending;
  };
  const editPen = (change: Partial<ToolSettings>) => {
    setPens((list) => list.map((p) => (p.id === penId() ? { ...p, tool: { ...p.tool, ...change } } : p)));
    clearTimeout(penWrite);
    penWrite = window.setTimeout(() => void writePensNow(), PEN_WRITE_MS);
  };
  // The selected pen's editor, beside the control that opened it.
  const openPenEditor = (e: Event) =>
    void presentPopover(e, () => <Show when={pen()}>{(p) => <PenEditor pen={p()} onChange={editPen} />}</Show>, {
      side: "right",
      alignment: "start",
      cssClass: "pen-editor-popover",
    });
  // Reads the presets again: on opening and when the window gains focus, as
  // another device may have changed the file. An edit not yet written wins.
  const loadPens = async () => {
    if (penWrite) return;
    const list = await readPens(root, doc.engine);
    setPens(list);
    if (!list.some((p) => p.id === penId())) setPenId(list[0]?.id ?? "");
    if (tool() === "" || (tool() !== ERASER && tool() !== SELECT && tool() !== TEXT && !list.some((p) => p.id === tool()))) setTool(penId());
  };
  const [view, setView] = createSignal<View>({ scale: 1, x: 0, y: 0 });
  const [pages, setPages] = createSignal(doc.pageCount());
  // How far, in CSS px, the view is pulled past the end of the last page.
  const [pull, setPull] = createSignal(0);

  // The view stops at the ends of the pages (docs/specs/tablet-ui.md, "Pages
  // in the editor"); content narrower or shorter than the canvas is centered.
  const clampView = (view: View): View => {
    const content = doc.contentSize();
    const width = content.width * view.scale, height = content.height * view.scale;
    const clampAxis = (at: number, size: number, viewport: number) =>
      size <= viewport ? (viewport - size) / 2 : Math.min(0, Math.max(viewport - size, at));
    return {
      scale: view.scale,
      x: clampAxis(view.x, width, element.clientWidth),
      y: clampAxis(view.y, height, element.clientHeight),
    };
  };
  const controller = new ViewController(
    { scale: 1, x: 0, y: 0 },
    (view) => {
      const clamped = clampView(view);
      // Movement past the end of the last page goes into the pull; moving
      // back takes it out before the view scrolls.
      const end = clampView({ ...view, y: -Infinity }).y;
      if (pull() > 0 || view.y < end) {
        const next = Math.max(0, pull() + end - view.y);
        setPull(next);
        if (next > 0) clamped.y = end;
      }
      controller.view = clamped;
      canvas?.setView(clamped.scale, 0, 0, clamped.scale, clamped.x, clamped.y);
      setView(clamped);
      setPages(doc.pageCount());
      refreshSelection();
    },
    () => releasePull(),
  );

  // Releasing past the threshold adds a page after the last one; the pull
  // springs back either way.
  const releasePull = () => {
    if (drawing()) {
      setPull(0);
      return;
    }
    const add = pull() >= PULL_THRESHOLD;
    setPull(0);
    if (add) edit(() => doc.insertPage(doc.pageCount()));
  };

  const fitScale = () => element.clientWidth / doc.contentSize().width;

  const fitWidth = () => controller.set({ scale: fitScale(), x: 0, y: 0 });

  // Zooms about the top left of the view, keeping the page at the top in place.
  const zoom = (factor: number) => {
    const { scale, y } = controller.view;
    const next = fitScale() * factor;
    controller.set({ scale: next, x: 0, y: (y * next) / scale });
  };

  const resize = () => {
    if (!canvas) return;
    const ratio = window.devicePixelRatio;
    element.width = Math.round(element.clientWidth * ratio);
    element.height = Math.round(element.clientHeight * ratio);
    canvas.setSurfaceSize(element.width, element.height, ratio);
    controller.set(controller.view);
  };

  const loop = () => {
    canvas?.render();
    frame = requestAnimationFrame(loop);
  };

  const origin = () => {
    const rect = element.getBoundingClientRect();
    return { x: rect.left, y: rect.top };
  };

  const onPointer = (e: PointerEvent) => {
    if (!canvas) return;
    const at = origin();
    if (controller.pointer(e, at)) {
      if (e.type === "pointerdown") element.setPointerCapture(e.pointerId);
      return;
    }
    if (tool() === TEXT) {
      if (e.type === "pointerdown") {
        e.preventDefault();
        const x = e.clientX - at.x, y = e.clientY - at.y;
        const existing = canvas.selectTextAt(x, y);
        refreshSelection();
        void presentModal(
          (dismiss) => <TextSheet initial={existing ? canvas!.selectedText() : ""} dismiss={dismiss}
            onSave={(value) => edit(() => existing ? canvas?.setSelectedText(value) : canvas?.insertText(value, x, y))} />,
          { cssClass: "form-sheet" },
        );
      }
      return;
    }
    if (e.type === "pointerdown") {
      element.setPointerCapture(e.pointerId);
      setSelection(null); // the actions return where the gesture leaves the selection
    }
    try {
      canvas.input(penSamples(e, at, capabilities(e.pointerType), ids));
    } catch (error) {
      void toast(error instanceof Error ? error.message : "Drawing input failed.", "danger");
      return;
    }
    if (e.type === "pointerup" || e.type === "pointercancel") {
      refreshSelection();
      saver.schedule();
      if (drawing()) refreshFigurePreview();
    }
  };

  const refreshFigurePreview = () => {
    if (!canvas || !drawing()) return;
    try {
      const scene = deserializeScene(canvas.figureScene());
      setFigureScene(scene);
      setFigureTikz(generateTikz(scene).source);
    } catch (error) {
      void toast(error instanceof Error ? error.message : "Could not preview drawing.", "danger");
    }
  };

  const toggleDrawing = () => {
    if (!canvas) return;
    try {
      if (!drawing()) {
        const page = currentPage();
        canvas.beginFigure(page);
        setFigurePage(page);
        setFigureOverlay(true);
        setDrawing(true);
        setFigureId("");
        setFigurePanel(true);
        selectTool(penId());
        refreshFigurePreview();
        return;
      }
      const scene = deserializeScene(canvas.figureScene());
      const source = generateTikz(scene).source;
      const id = canvas.completeFigure(JSON.stringify(scene), source);
      setDrawing(false);
      setFigureScene(scene.objects.length ? scene : null);
      setFigureTikz(scene.objects.length ? source : "");
      setFigureId(id);
      setFigurePanel(Boolean(id));
      setFigureOverlay(Boolean(id));
      edit(() => {});
      refreshSelection();
    } catch (error) {
      void toast(error instanceof Error ? error.message : "Could not complete drawing.", "danger");
    }
  };

  const refreshSelection = () => {
    const selected = canvas?.selection() ?? null;
    setSelection(selected);
    if (!canvas || drawing() || !selected) return;
    try {
      const id = canvas.selectedFigure();
      if (!id) return;
      setFigureOverlay(false);
      if (id === figureId()) return;
      const scene = deserializeScene(utf8.decode(doc.asset(`assets/${id}.scene.json`)));
      const source = utf8.decode(doc.asset(`assets/${id}.tikz`));
      setFigureScene(scene);
      setFigureTikz(source);
      setFigureId(id);
      setFigurePage(selected.page);
      setFigureOverlay(false);
      setFigurePanel(true);
    } catch (error) {
      void toast(error instanceof Error ? error.message : "Could not open figure.", "danger");
    }
  };

  const figureBox = () => {
    if (!figureOverlay()) return null;
    const scene = figureScene();
    const bounds = scene && sceneBounds(scene);
    if (!bounds) return null;
    const page = doc.pageRect(figurePage());
    const { scale, x, y } = view();
    const inset = 3 * scale;
    return {
      left: `${x + (page.x + bounds.minX) * scale - inset}px`,
      top: `${y + (page.y + bounds.minY) * scale - inset}px`,
      width: `${Math.max(2 * inset, (bounds.maxX - bounds.minX) * scale + 2 * inset)}px`,
      height: `${Math.max(2 * inset, (bounds.maxY - bounds.minY) * scale + 2 * inset)}px`,
    };
  };

  // A wheel or trackpad scroll has no release event: the pull is released
  // when no wheel event has come for WHEEL_RELEASE_MS.
  let wheelRelease = 0;
  const onWheel = (e: WheelEvent) => {
    e.preventDefault();
    controller.wheel(e, origin());
    clearTimeout(wheelRelease);
    wheelRelease = window.setTimeout(releasePull, WHEEL_RELEASE_MS);
  };

  // The page at the middle of the view; the last page below the pages.
  const currentPage = () => {
    view();
    pages();
    if (!canvas) return 0;
    const page = canvas.pageAt(element.clientWidth / 2, element.clientHeight / 2);
    const count = doc.pageCount();
    return page < 0 || page >= count ? count - 1 : page;
  };

  const edit = (change: () => void) => {
    change();
    controller.set(controller.view);
    saver.schedule();
  };

  // The system clipboard holds the selection as SVG text (#24).
  const copy = (cut: boolean) => {
    if (!canvas) return;
    const svg = canvas.copySelection(cut);
    if (!svg) return;
    void navigator.clipboard.writeText(svg);
    if (cut) edit(() => {});
  };
  // Pastes at the middle of the view.
  const paste = (svg: string) => {
    if (drawing()) {
      void toast("Complete the drawing before pasting.");
      return;
    }
    const target = canvas;
    if (!target || !svg) return;
    edit(() => target.paste(svg, element.clientWidth / 2, element.clientHeight / 2));
  };
  const insertImage = async (file: File) => {
    if (drawing()) {
      await toast("Complete the drawing before inserting an image.");
      return;
    }
    if (file.type !== "image/png" && file.type !== "image/jpeg") {
      await toast("Choose a PNG or JPEG image", "danger");
      return;
    }
    try {
      const bitmap = await createImageBitmap(file);
      const page = doc.pageRect(currentPage());
      const scale = Math.min(1, (page.width * 0.8) / bitmap.width, (page.height * 0.8) / bitmap.height);
      const width = Math.round(bitmap.width * scale * 100) / 100;
      const height = Math.round(bitmap.height * scale * 100) / 100;
      bitmap.close();
      const url = await new Promise<string>((resolve, reject) => {
        const reader = new FileReader();
        reader.onerror = () => reject(reader.error);
        reader.onload = () => typeof reader.result === "string" ? resolve(reader.result) : reject(new Error("Could not read image"));
        reader.readAsDataURL(file);
      });
      // SVG 2's image element carries the data URL only through the existing
      // clipboard path. The engine stores its bytes in assets/ on paste.
      paste(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1"><g id="import"><image href="${url}" x="${-width - 1}" y="${-height - 1}" width="${width}" height="${height}"/></g></svg>`);
    } catch {
      await toast("Could not insert image", "danger");
    }
  };
  // Ctrl+V: the paste event carries the clipboard text without a permission prompt.
  const onPaste = (e: ClipboardEvent) => {
    if (e.composedPath().some((target) => target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement ||
      (target instanceof HTMLElement && target.tagName === "ION-TEXTAREA"))) return;
    const text = e.clipboardData?.getData("text/plain");
    if (!text) return;
    e.preventDefault();
    paste(text);
  };

  // Scrolls page `index` into view when it is not already visible.
  const showPage = (index: number) => {
    if (index < 0) return;
    const rect = doc.pageRect(index);
    const { scale, x, y } = controller.view;
    const top = y + rect.y * scale, bottom = top + rect.height * scale;
    if (bottom > 0 && top < element.clientHeight) return;
    controller.set({ scale, x, y: -rect.y * scale });
  };

  // Puts the top of page `index` at the top of the view.
  const goToPage = (index: number) => {
    if (drawing()) {
      void toast("Complete the drawing before changing pages.");
      return;
    }
    if (index < 0 || index >= doc.pageCount()) return;
    const { scale, x } = controller.view;
    controller.set({ scale, x, y: -doc.pageRect(index).y * scale });
  };

  const history = (step: "undo" | "redo") => {
    if (drawing()) {
      void toast("Complete the drawing before changing history.");
      return;
    }
    const moved = step === "undo" ? doc.undo() : doc.redo();
    if (!moved) return;
    edit(() => showPage(moved.page));
  };

  const onKey = (e: KeyboardEvent) => {
    if (e.composedPath().some((target) => target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement ||
      (target instanceof HTMLElement && target.tagName === "ION-TEXTAREA"))) return;
    const key = e.key.toLowerCase();
    if ((key === "delete" || key === "backspace") && selection()) {
      e.preventDefault();
      edit(() => canvas?.deleteSelection());
      return;
    }
    if (key === "escape") {
      canvas?.clearSelection();
      refreshSelection();
      return;
    }
    if (!(e.ctrlKey || e.metaKey)) return;
    const commands: Record<string, () => void> = {
      z: () => history(e.shiftKey ? "redo" : "undo"),
      a: () => {
        canvas?.selectAll(currentPage());
        refreshSelection();
      },
      c: () => copy(false),
      x: () => copy(true),
      d: () => edit(() => canvas?.duplicateSelection()),
    };
    if (!commands[key]) return;
    e.preventDefault();
    commands[key]();
  };

  onMount(() => {
    window.addEventListener("keydown", onKey);
    window.addEventListener("paste", onPaste);
    onCleanup(() => {
      window.removeEventListener("keydown", onKey);
      window.removeEventListener("paste", onPaste);
    });
    canvas = doc.createCanvas("#ink-canvas");
    canvas.setUtcOffset(performance.timeOrigin);
    createEffect(() => {
      const current = pen();
      if (current) canvas?.setTool(current.tool);
    });
    createEffect(() => canvas?.setEraser(ERASERS[eraser()].kind, tool() === ERASER));
    createEffect(() => canvas?.setSelector(SELECTORS[selector()].kind, tool() === SELECT));
    const onFocus = () => void loadPens();
    window.addEventListener("focus", onFocus);
    onCleanup(() => window.removeEventListener("focus", onFocus));
    void loadPens();
    const observer = new ResizeObserver(resize);
    observer.observe(area);
    resize();
    fitWidth();
    frame = requestAnimationFrame(loop);
    onCleanup(() => {
      observer.disconnect();
      cancelAnimationFrame(frame);
    });
  });

  // Saves and frees the notebook, then `next` moves to another screen.
  const leave = async (next: () => void) => {
    if (drawing()) {
      await toast("Complete the drawing before leaving this note.");
      return;
    }
    await saver.save();
    if (penWrite) await writePensNow();
    await penWritePending;
    canvas?.free();
    canvas = undefined;
    doc.free();
    next();
  };

  const isOpen = (path: string[]) => path.join("/") === props.notebook.path.join("/");
  const zoomLabel = () => (element ? `${Math.round((view().scale / fitScale()) * 100)}%` : "100%");
  const tagColor = (name: string) => props.allTags.find((t) => t.name === name)?.color ?? "#8A8F98";

  const pageMenu = (e: Event) => {
    if (drawing()) {
      void toast("Complete the drawing before changing pages.");
      return;
    }
    void presentPopover(e, (dismiss) => (
      <IonList lines="full">
        <MenuItem label="Paste" dismiss={dismiss} onSelect={() => void navigator.clipboard.readText().then(paste)} />
        <MenuItem label="Insert page before" dismiss={dismiss} onSelect={() => edit(() => doc.insertPage(currentPage()))} />
        <MenuItem label="Insert page after" dismiss={dismiss} onSelect={() => edit(() => doc.insertPage(currentPage() + 1))} />
        <MenuItem label="Delete page" dismiss={dismiss} onSelect={() => edit(() => doc.pageCount() > 1 && doc.deletePage(currentPage()))} />
        <MenuItem
          label="Move page up"
          dismiss={dismiss}
          onSelect={() => edit(() => currentPage() > 0 && doc.movePage(currentPage(), currentPage() - 1))}
        />
        <MenuItem
          label="Move page down"
          dismiss={dismiss}
          onSelect={() => edit(() => currentPage() < doc.pageCount() - 1 && doc.movePage(currentPage(), currentPage() + 1))}
        />
        <MenuItem label="Page size: A4" dismiss={dismiss} onSelect={() => edit(() => doc.setPageSize(PageSize.a4))} />
        <MenuItem label="Page size: Letter" dismiss={dismiss} onSelect={() => edit(() => doc.setPageSize(PageSize.letter))} />
      </IonList>
    ));
  };

  const titleMenu = (e: Event) =>
    void presentPopover(e, (dismiss) => (
      <IonList lines="full">
        <For each={props.folderNotes}>
          {(note) => (
            <MenuItem
              label={note.name}
              checked={isOpen(note.path)}
              dismiss={dismiss}
              onSelect={() => !isOpen(note.path) && void leave(() => props.onSelectTab(note.path))}
            />
          )}
        </For>
      </IonList>
    ));

  const tagMenu = (e: Event) =>
    void presentPopover(e, () => (
      <IonList lines="full">
        <For each={props.allTags}>
          {(tag) => (
            <IonItem>
              <span slot="start" class="tag-dot" style={{ background: tag.color }} />
              <IonCheckbox justify="space-between" checked={props.tags.includes(tag.name)} on:ionChange={() => props.onToggleTag(tag.name)}>
                {tag.name}
              </IonCheckbox>
            </IonItem>
          )}
        </For>
        <IonItem button detail={false} onClick={() => props.onNewTag()}>
          <IonIcon slot="start" icon={add} />
          <IonLabel>New Tag…</IonLabel>
        </IonItem>
      </IonList>
    ));

  const openNotePicker = () =>
    void presentModal(
      (dismiss) => <NotePicker notes={props.libraryNotes} dismiss={dismiss} onOpen={(path) => !isOpen(path) && void leave(() => props.onSelectTab(path))} />,
      { cssClass: "form-sheet" },
    );

  const exportPdf = (first: number, count: number) => {
    try {
      const pdf = doc.exportPdf(props.notebook.name, first, count);
      const url = URL.createObjectURL(new Blob([pdf], { type: "application/pdf" }));
      const link = document.createElement("a");
      link.href = url;
      link.download = `${props.notebook.name}.pdf`;
      link.click();
      window.setTimeout(() => URL.revokeObjectURL(url), 10_000);
    } catch (error) {
      void toast(error instanceof Error ? error.message : "PDF export failed.", "danger");
    }
  };

  const share = () => void presentModal((dismiss) => <PdfExportSheet pages={doc.pageCount()} dismiss={dismiss} onExport={exportPdf} />, { cssClass: "form-sheet" });

  return (
    <div class="editor ion-page">
      <IonHeader class="editor-header">
        <IonToolbar>
          <IonButtons slot="start">
            <IonButton aria-label="Library" onClick={() => void leave(props.onLibrary)}>
              <IonIcon slot="start" icon={chevronBack} />
              <AppMark />
            </IonButton>
            <IonButton class="editor-title" color="dark" aria-label="Notes in this notebook" onClick={titleMenu}>
              <span class="editor-title-text">
                <span class="editor-folder">{props.folderName}</span>
                <IonNote class="editor-subtitle">
                  {props.folderDescription ? `${props.folderDescription} · ` : ""}{noteCount(props.folderNotes.length)}
                </IonNote>
              </span>
              <IonIcon slot="end" icon={chevronDown} />
            </IonButton>
          </IonButtons>
          <div class="tabs" role="tablist" aria-label="Open notes">
            <For each={props.tabs}>
              {(tab) => (
                <div class={isOpen(tab.path) ? "tab selected" : "tab"} aria-current={isOpen(tab.path) ? "page" : undefined}>
                  <IonButton
                    fill="clear"
                    size="small"
                    color={isOpen(tab.path) ? "primary" : "medium"}
                    class="tab-label"
                    role="tab"
                    aria-selected={isOpen(tab.path)}
                    onClick={() => !isOpen(tab.path) && void leave(() => props.onSelectTab(tab.path))}
                  >
                    <span class="tab-text">{tab.name}</span>
                  </IonButton>
                  <IonButton
                    fill="clear"
                    size="small"
                    color="medium"
                    aria-label={`Close ${tab.name}`}
                    onClick={() => (isOpen(tab.path) ? void leave(() => props.onCloseTab(tab.path)) : props.onCloseTab(tab.path))}
                  >
                    <IonIcon slot="icon-only" icon={close} />
                  </IonButton>
                </div>
              )}
            </For>
            <IonButton fill="clear" size="small" aria-label="Open another note" onClick={openNotePicker}>
              <IonIcon slot="icon-only" icon={add} />
            </IonButton>
          </div>
          <IonButtons slot="end">
            <IonButton aria-label="Share" onClick={share}>
              <IonIcon slot="icon-only" icon={shareOutline} />
            </IonButton>
            <IonButton aria-label="Page actions" onClick={pageMenu}>
              <IonIcon slot="icon-only" icon={ellipsisHorizontal} />
            </IonButton>
          </IonButtons>
        </IonToolbar>
      </IonHeader>
      <div class="editor-body">
        <aside class="tool-rail" aria-label="Tools">
          <IonList lines="none" class="tools">
            <For each={pens()}>
              {(p) => (
                <ToolItem
                  label={p.name}
                  detail={sizeLabel(p.tool.size)}
                  selected={tool() === p.id}
                  icon={penIcon(p.tool.brush, hex(p.tool.rgb))}
                  // A tap on the selected pen opens its editor, as in GoodNotes and Noteful.
                  onSelect={(e) => (tool() === p.id ? openPenEditor(e) : selectTool(p.id))}
                />
              )}
            </For>
            <ToolItem label="Eraser" detail={ERASERS[eraser()].label} selected={tool() === ERASER} icon={<EraserIcon size={22} />} onSelect={() => selectTool(ERASER)} />
            <ToolItem label="Lasso" detail={SELECTORS[selector()].label} selected={tool() === SELECT} icon={<Lasso size={22} />} onSelect={() => selectTool(SELECT)} />
            <ToolItem label="Drawing" detail={drawing() ? "Tap to complete" : "TikZ figure"} selected={drawing()} icon={<DraftingCompass size={22} />} onSelect={toggleDrawing} />
            <ToolItem label="Image" selected={false} icon={<ImageIcon size={22} />} onSelect={() => drawing() ? void toast("Complete the drawing before inserting an image.") : imageInput.click()} />
            <ToolItem label="Text" selected={tool() === TEXT} icon={<TextIcon size={22} />} onSelect={() => drawing() ? void toast("Complete the drawing before adding page text.") : selectTool(TEXT)} />
          </IonList>
          <input ref={imageInput} type="file" accept="image/png,image/jpeg" hidden onChange={(event) => {
            const file = event.currentTarget.files?.[0];
            event.currentTarget.value = "";
            if (file) void insertImage(file);
          }} />
          <Show when={tool() === ERASER}>
            <IonList lines="none" class="tools kinds" aria-label="Eraser">
              <For each={Object.keys(ERASERS) as EraserId[]}>
                {(id) => <ToolItem label={ERASERS[id].label} selected={eraser() === id} icon={<span />} onSelect={() => setEraser(id)} />}
              </For>
            </IonList>
          </Show>
          <Show when={tool() === SELECT}>
            <IonList lines="none" class="tools kinds" aria-label="Selection">
              <For each={Object.keys(SELECTORS) as SelectorId[]}>
                {(id) => <ToolItem label={SELECTORS[id].label} selected={selector() === id} icon={<span />} onSelect={() => setSelector(id)} />}
              </For>
            </IonList>
          </Show>
          <Swatches value={pen()?.tool.rgb} onChange={(rgb) => editPen({ rgb })}>
            <IonButton class="swatch add" shape="round" fill="outline" color="medium" aria-label="Custom color" onClick={openPenEditor}>
              <IonIcon slot="icon-only" icon={add} />
            </IonButton>
          </Swatches>
        </aside>
        <div class="canvas-area" ref={area}>
          <canvas
            id="ink-canvas"
            ref={element}
            onPointerDown={onPointer}
            onPointerMove={onPointer}
            onPointerUp={onPointer}
            onPointerCancel={onPointer}
            onWheel={onWheel}
            onContextMenu={(e) => e.preventDefault()}
          />
          <Show when={figureBox()}>{(box) => <div class="figure-page-bounds" classList={{ "is-capturing": drawing() }} style={box()} aria-label={drawing() ? "Drawing bounds" : `Figure ${figureId()} bounds`} />}</Show>
          <div class="page-tags" aria-label="Tags">
            <For each={props.tags}>
              {(tag) => (
                <IonChip class="tag-chip" style={{ "--chip": tagColor(tag) }}>
                  <IonLabel>#{tag}</IonLabel>
                </IonChip>
              )}
            </For>
            <IonButton class="chip-add" size="small" fill="outline" color="medium" shape="round" aria-label="Add tag" onClick={tagMenu}>
              <IonIcon slot="icon-only" icon={add} />
            </IonButton>
          </div>
          <Show when={selection()}>
            {(sel) => (
              <div
                class="selection-bar bar-group"
                role="toolbar"
                aria-label="Selection actions"
                style={{ left: `${sel().x + sel().width / 2}px`, top: `${sel().y + sel().height + 12}px` }}
              >
                <IonButton fill="clear" size="small" aria-label="Copy" title="Copy (Ctrl+C)" onClick={() => copy(false)}>
                  <IonIcon slot="icon-only" icon={copyOutline} />
                </IonButton>
                <IonButton fill="clear" size="small" aria-label="Cut" title="Cut (Ctrl+X)" onClick={() => copy(true)}>
                  <IonIcon slot="icon-only" icon={cutOutline} />
                </IonButton>
                <IonButton
                  fill="clear"
                  size="small"
                  aria-label="Duplicate"
                  title="Duplicate (Ctrl+D)"
                  onClick={() => edit(() => canvas?.duplicateSelection())}
                >
                  <IonIcon slot="icon-only" icon={duplicateOutline} />
                </IonButton>
                <IonButton
                  fill="clear"
                  size="small"
                  color="danger"
                  aria-label="Delete"
                  title="Delete (Del)"
                  onClick={() => edit(() => canvas?.deleteSelection())}
                >
                  <IonIcon slot="icon-only" icon={trashOutline} />
                </IonButton>
              </div>
            )}
          </Show>
          <div
            class="pull-indicator"
            data-active={pull() > 0 ? "" : undefined}
            data-ready={pull() >= PULL_THRESHOLD ? "" : undefined}
            style={{ height: `${Math.min(pull(), 1.5 * PULL_THRESHOLD)}px` }}
          >
            <IonIcon icon={add} />
            {pull() >= PULL_THRESHOLD ? "Release to add a page" : "Pull to add a page"}
          </div>
          <div class="bottom-bar">
            <div class="bar-group">
              <IonButton fill="clear" size="small" color="dark" aria-label="Undo" title="Undo (Ctrl+Z)" onClick={() => history("undo")}>
                <IonIcon slot="icon-only" icon={arrowUndo} />
              </IonButton>
              <IonButton fill="clear" size="small" color="dark" aria-label="Redo" title="Redo (Shift+Ctrl+Z)" onClick={() => history("redo")}>
                <IonIcon slot="icon-only" icon={arrowRedo} />
              </IonButton>
            </div>
            <BarMenu
              label="Zoom"
              text={zoomLabel()}
              items={(dismiss) => (
                <>
                  <MenuItem label="Fit width" dismiss={dismiss} onSelect={fitWidth} />
                  <For each={ZOOMS}>{(factor) => <MenuItem label={`${factor * 100}%`} dismiss={dismiss} onSelect={() => zoom(factor)} />}</For>
                </>
              )}
            />
            <BarMenu
              label="Paper"
              icon={gridOutline}
              text={paperLabel(template())}
              items={(dismiss) => (
                <For each={templates()}>
                  {(name) => (
                    <MenuItem
                      label={paperLabel(name)}
                      checked={template() === name}
                      dismiss={dismiss}
                      onSelect={() => {
                        if (drawing()) {
                          void toast("Complete the drawing before changing paper.");
                          return;
                        }
                        void applyTemplate(root, doc, name).then(() => {
                          setTemplate(name);
                          edit(() => {});
                        });
                      }}
                    />
                  )}
                </For>
              )}
            />
            <div class="bar-spacer" />
            <div class="bar-group">
              <IonButton fill="clear" size="small" color="dark" aria-label="Previous page" onClick={() => goToPage(currentPage() - 1)}>
                <IonIcon slot="icon-only" icon={chevronBack} />
              </IonButton>
              <span class="page-indicator" aria-label="Page">
                {currentPage() + 1} / {pages()}
              </span>
              <IonButton fill="clear" size="small" color="dark" aria-label="Next page" onClick={() => goToPage(currentPage() + 1)}>
                <IonIcon slot="icon-only" icon={chevronForward} />
              </IonButton>
            </div>
          </div>
        </div>
        <Show when={figurePanel()}>
          <aside class="figure-sidebar" aria-label="TikZ drawing preview">
            <div class="figure-sidebar-header">
              <div>
                <h2>{drawing() ? "Drawing mode" : "TikZ figure"}</h2>
                <p>{drawing() ? "Draw on this page, then complete the figure." : "Figure saved with this note."}</p>
              </div>
              <Show when={!drawing()}>
                <IonButton fill="clear" size="small" aria-label="Close figure preview" onClick={() => setFigurePanel(false)}>
                  <IonIcon slot="icon-only" icon={close} />
                </IonButton>
              </Show>
            </div>
            <div class="figure-sidebar-content">
              <h3>Approximate preview</h3>
              <div class="figure-preview">
                <Show when={figureScene()?.objects.length} fallback={<p class="figure-empty">Draw with a pen to start the figure.</p>}>
                  <FigurePreview scene={figureScene()!} />
                </Show>
              </div>
              <div class="figure-source-title">
                <h3>TikZ source</h3>
                <IonButton fill="clear" size="small" disabled={!figureTikz()} onClick={() => void navigator.clipboard.writeText(figureTikz())}>Copy</IonButton>
              </div>
              <textarea class="figure-source" aria-label="Generated TikZ source" readOnly value={figureTikz()} spellcheck={false} />
              <p class="figure-preview-note">The preview shows scene geometry. It does not compile TeX.</p>
            </div>
          </aside>
        </Show>
      </div>
    </div>
  );
}
