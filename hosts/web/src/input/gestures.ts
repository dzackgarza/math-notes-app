// The view over the pages: content (pt) -> view (CSS px) by a scale and a
// translation, moved by one-finger pan, two-finger pinch, and the wheel. Follows
// MDN "Pinch zoom gestures" (Pointer Events): the pointers are kept in a
// cache by pointerId, and each move compares the two with their last
// positions.

// 100 % zoom is the printed size: 1 pt = 96/72 CSS px.
export const PRINT_SCALE = 96 / 72;
export const MIN_SCALE = 0.25 * PRINT_SCALE;
export const MAX_SCALE = 8 * PRINT_SCALE;

export interface View {
  scale: number;
  x: number; // view position of content (0, 0)
  y: number;
}

interface Point {
  x: number;
  y: number;
}

export class ViewController {
  view: View;
  private readonly touches = new Map<number, Point>();
  private readonly onChange: (view: View) => void;
  private readonly onRelease: () => void;

  // `onRelease` runs when the last finger of a touch gesture lifts.
  constructor(view: View, onChange: (view: View) => void, onRelease: () => void) {
    this.view = view;
    this.onChange = onChange;
    this.onRelease = onRelease;
  }

  // Returns whether the event was a touch the controller took.
  pointer(e: PointerEvent, origin: Point): boolean {
    if (e.pointerType !== "touch") {
      // A pen or mouse going down ends any gesture.
      if (e.type === "pointerdown") this.touches.clear();
      return false;
    }
    const at = { x: e.clientX - origin.x, y: e.clientY - origin.y };
    switch (e.type) {
      case "pointerdown":
        this.touches.set(e.pointerId, at);
        break;
      case "pointermove": {
        const before = this.touches.get(e.pointerId);
        if (!before) break;
        const other = [...this.touches].find(([id]) => id !== e.pointerId)?.[1];
        this.touches.set(e.pointerId, at);
        if (other && this.touches.size === 2) this.twoFingers(before, at, other);
        else if (this.touches.size === 1) {
          this.set({ ...this.view, x: this.view.x + at.x - before.x, y: this.view.y + at.y - before.y });
        }
        break;
      }
      default:
        if (this.touches.delete(e.pointerId) && this.touches.size === 0) this.onRelease();
    }
    return true;
  }

  wheel(e: WheelEvent, origin: Point): void {
    if (e.ctrlKey) {
      // Trackpad pinch, and ctrl + wheel: zoom about the pointer.
      this.zoomAbout({ x: e.clientX - origin.x, y: e.clientY - origin.y }, Math.exp(-e.deltaY / 100));
    } else {
      this.set({ ...this.view, x: this.view.x - e.deltaX, y: this.view.y - e.deltaY });
    }
  }

  set(view: View): void {
    this.view = view;
    this.onChange(view);
  }

  // One finger moved from `before` to `after` while the other stays at
  // `still`: the content under the midpoint follows it, scaled by the
  // change in distance.
  private twoFingers(before: Point, after: Point, still: Point): void {
    const mid0 = { x: (before.x + still.x) / 2, y: (before.y + still.y) / 2 };
    const mid1 = { x: (after.x + still.x) / 2, y: (after.y + still.y) / 2 };
    const d0 = Math.hypot(before.x - still.x, before.y - still.y);
    const d1 = Math.hypot(after.x - still.x, after.y - still.y);
    const { scale, x, y } = this.view;
    const next = clamp(scale * (d0 > 0 ? d1 / d0 : 1), MIN_SCALE, MAX_SCALE);
    // Content point under the old midpoint lands under the new one.
    const cx = (mid0.x - x) / scale;
    const cy = (mid0.y - y) / scale;
    this.set({ scale: next, x: mid1.x - cx * next, y: mid1.y - cy * next });
  }

  private zoomAbout(at: Point, factor: number): void {
    const { scale, x, y } = this.view;
    const next = clamp(scale * factor, MIN_SCALE, MAX_SCALE);
    this.set({ scale: next, x: at.x - ((at.x - x) / scale) * next, y: at.y - ((at.y - y) / scale) * next });
  }
}

function clamp(value: number, low: number, high: number): number {
  return Math.min(Math.max(value, low), high);
}
