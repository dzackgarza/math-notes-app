// The notebook owns figure source; the pinned workbench owns visual editing.
import type { OpenNotebook } from './notebook.ts';

interface EditorMessage {
  event: string;
  action?: string;
  status?: string;
  sessionId?: string;
  revision?: number;
  requestId?: string;
  source?: string;
  paperSource?: string;
  error?: string;
  message?: string;
}

export class FigureEditor extends EventTarget {
  private readonly note: OpenNotebook;
  private readonly id: string;
  private readonly frame: HTMLIFrameElement;
  private readonly sessionId = crypto.randomUUID();
  private readonly revision = 1;
  private readonly requests = new Map<string, {
    resolve: (value: { source: string; paperSource: string }) => void;
    reject: (reason: Error) => void;
    timer: ReturnType<typeof setTimeout>;
  }>();
  ready = false;
  error = '';
  source: string;
  paperSource = '';
  private saving = false;

  private readonly receive = (event: MessageEvent<string>) => {
    if (event.source !== this.frame.contentWindow || event.origin !== location.origin || typeof event.data !== 'string') return;
    let message: EditorMessage;
    try { message = JSON.parse(event.data); }
    catch { return; }
    if (message.event === 'init') {
      this.send({ action: 'load', source: this.source,
        fileName: `${this.id}.tikz`, autosave: 0 });
      return;
    }
    if (message.sessionId !== this.sessionId || message.revision !== this.revision) return;
    if (message.event === 'loaded') {
      if (typeof message.paperSource === 'string') {
        this.paperSource = message.paperSource;
        this.ready = true;
      } else this.error = 'The figure editor did not return its paper source.';
    }
    if (message.event === 'reply' && message.action === 'load' && message.status === 'failed') {
      this.error = `Figure editor load failed: ${message.error ?? 'unknown error'}`;
    }
    if (message.event === 'reply' && message.action === 'source' && message.requestId) {
      const request = this.requests.get(message.requestId);
      if (request) {
        clearTimeout(request.timer);
        this.requests.delete(message.requestId);
        if (message.status === 'ok' && typeof message.source === 'string' &&
            typeof message.paperSource === 'string') {
          request.resolve({ source: message.source, paperSource: message.paperSource });
        }
        else request.reject(new Error(message.error ?? 'The figure source is unavailable.'));
      }
    }
    if (this.ready && (message.event === 'change' || message.event === 'save') && typeof message.source === 'string') {
      try {
        if (typeof message.paperSource !== 'string') throw new Error('The figure editor did not return its paper source.');
        this.persist(message.source);
        this.paperSource = message.paperSource;
      }
      catch (error) { this.error = error instanceof Error ? error.message : String(error); }
    }
    if (message.event === 'error') this.error = message.message ?? 'Figure editor error.';
    this.dispatchEvent(new Event('change'));
  };

  constructor(note: OpenNotebook, id: string, frame: HTMLIFrameElement) {
    super();
    this.note = note;
    this.id = id;
    this.frame = frame;
    this.source = note.document.figureSource(id);
    window.addEventListener('message', this.receive);
    frame.title = 'TikZ figure editor';
    frame.src = new URL('tikz-workbench/hosted.html', document.baseURI).href;
  }

  private send(command: Record<string, unknown>): void {
    this.frame.contentWindow!.postMessage(JSON.stringify({
      ...command, sessionId: this.sessionId, revision: this.revision,
      requestId: crypto.randomUUID(),
    }), location.origin);
  }

  private persist(source: string): void {
    this.note.document.saveFigureDraft(this.id, source);
    this.note.saver.schedule();
    this.source = source;
    this.error = '';
  }

  private requestSource(): Promise<{ source: string; paperSource: string }> {
    const requestId = crypto.randomUUID();
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.requests.delete(requestId);
        reject(new Error('The figure editor did not return its source.'));
      }, 12000);
      this.requests.set(requestId, { resolve, reject, timer });
      this.frame.contentWindow!.postMessage(JSON.stringify({
        action: 'source', sessionId: this.sessionId, revision: this.revision, requestId,
      }), location.origin);
    });
  }

  async latestPaperSource(): Promise<string> {
    if (!this.ready) throw new Error('The figure editor is still loading.');
    const { source, paperSource } = await this.requestSource();
    this.persist(source);
    this.paperSource = paperSource;
    this.dispatchEvent(new Event('change'));
    return paperSource;
  }

  async save(): Promise<void> {
    if (!this.ready) throw new Error('The figure editor is still loading.');
    if (this.saving) throw new Error('The figure source is already saving.');
    this.saving = true;
    try {
      await this.latestPaperSource();
      await this.note.saver.save();
    } catch (error) {
      this.error = error instanceof Error ? error.message : String(error);
      this.dispatchEvent(new Event('change'));
      throw error;
    } finally {
      this.saving = false;
    }
  }

  dispose(): void {
    window.removeEventListener('message', this.receive);
    for (const request of this.requests.values()) {
      clearTimeout(request.timer);
      request.reject(new Error('The figure editor closed before saving.'));
    }
    this.requests.clear();
  }
}

export function mountFigureEditor(note: OpenNotebook, id: string, frame: HTMLIFrameElement): FigureEditor {
  return new FigureEditor(note, id, frame);
}
