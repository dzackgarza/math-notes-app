// TeXlyre embed b98714d3 README.md: load/save and source change messages.
import type { OpenNotebook } from './notebook.ts';
import { compileFigure } from './figure-compile.ts';

interface EditorMessage {
  event: 'init' | 'loaded' | 'change' | 'autosave' | 'save' | 'export';
  source?: string;
  svg?: string;
}

export class FigureEditor extends EventTarget {
  private readonly note: OpenNotebook;
  private readonly id: string;
  private readonly frame: HTMLIFrameElement;
  ready = false;
  error = '';
  compiling = false;
  progress = '';
  private pendingSave: { resolve: () => void; reject: (reason: Error) => void } | null = null;
  private readonly receive = (event: MessageEvent<string>) => {
    if (event.source !== this.frame.contentWindow || event.origin !== location.origin || typeof event.data !== 'string') return;
    void this.accept(event.data).catch(error => {
      this.error = error instanceof Error ? error.message : String(error);
      this.pendingSave?.reject(new Error(this.error));
      this.pendingSave = null;
      this.dispatchEvent(new Event('change'));
    });
  };

  constructor(note: OpenNotebook, id: string, frame: HTMLIFrameElement) {
    super();
    this.note = note;
    this.id = id;
    this.frame = frame;
    window.addEventListener('message', this.receive);
    frame.title = 'TikZ figure editor';
    frame.src = new URL('tikz-editor/index.html', document.baseURI).href;
  }

  private async accept(data: string): Promise<void> {
    const message: EditorMessage = JSON.parse(data);
    if (message.event === 'init') {
      this.frame.contentWindow!.postMessage(JSON.stringify({ action: 'load', source: this.note.document.figureSource(this.id), autosave: 1 }), location.origin);
      return;
    }
    if (message.event === 'loaded') this.ready = true;
    if (!this.ready) return;
    if (['change', 'autosave', 'save'].includes(message.event) && typeof message.source === 'string') {
      this.note.document.saveFigureDraft(this.id, message.source);
      this.note.saver.schedule();
      if (message.event === 'save') {
        await this.note.saver.save();
        this.pendingSave?.resolve();
        this.pendingSave = null;
      }
    }
    this.error = '';
    this.dispatchEvent(new Event('change'));
  }

  save(): Promise<void> {
    if (!this.ready) return Promise.reject(new Error('The figure editor is still loading.'));
    if (this.pendingSave) return Promise.reject(new Error('The figure source is already saving.'));
    return new Promise((resolve, reject) => {
      this.pendingSave = { resolve, reject };
      this.frame.contentWindow!.postMessage(JSON.stringify({ action: 'save' }), location.origin);
    });
  }

  async compile(): Promise<void> {
    if (this.compiling) return;
    this.compiling = true;
    this.error = '';
    this.dispatchEvent(new Event('change'));
    try {
      await this.save();
      await compileFigure(this.note, this.id, message => {
        this.progress = message;
        this.dispatchEvent(new Event('change'));
      });
    } finally {
      this.compiling = false;
      this.dispatchEvent(new Event('change'));
    }
  }

  dispose(): void {
    window.removeEventListener('message', this.receive);
    this.pendingSave?.reject(new Error('The figure editor closed before saving.'));
    this.pendingSave = null;
  }
}

export function mountFigureEditor(note: OpenNotebook, id: string, frame: HTMLIFrameElement): FigureEditor {
  return new FigureEditor(note, id, frame);
}
