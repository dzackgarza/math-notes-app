// Finger pan and two-finger pinch zoom on synthetic touch pointers, in Chromium.
import { expect, test } from "vitest";

import { MAX_SCALE, ViewController, type View } from "./gestures.ts";

const origin = { x: 0, y: 0 };

function touch(type: string, pointerId: number, x: number, y: number): PointerEvent {
  return new PointerEvent(type, { pointerId, pointerType: "touch", clientX: x, clientY: y, buttons: type === "pointerup" ? 0 : 1 });
}

function controller(): { control: ViewController; views: View[] } {
  const views: View[] = [];
  const control = new ViewController({ scale: 1, x: 0, y: 0 }, (v) => views.push(v), () => {});
  return { control, views };
}

test("spreading two fingers zooms about their midpoint", () => {
  const { control } = controller();
  control.pointer(touch("pointerdown", 1, 100, 100), origin);
  control.pointer(touch("pointerdown", 2, 200, 100), origin);
  control.pointer(touch("pointermove", 2, 300, 100), origin);
  // Distance 100 -> 200 doubles the scale; content x = 150, under the old
  // midpoint, lands under the new one at 200.
  expect(control.view.scale).toBeCloseTo(2, 9);
  expect(control.view.x + 150 * control.view.scale).toBeCloseTo(200, 9);
});

test("moving two fingers together pans without zooming", () => {
  const { control } = controller();
  control.pointer(touch("pointerdown", 1, 100, 100), origin);
  control.pointer(touch("pointerdown", 2, 200, 100), origin);
  control.pointer(touch("pointermove", 1, 100, 160), origin);
  control.pointer(touch("pointermove", 2, 200, 160), origin);
  expect(control.view.scale).toBeCloseTo(1, 9);
  expect(control.view.y).toBeCloseTo(60, 9);
  expect(control.view.x).toBeCloseTo(0, 9);
});

test("one finger pans while the scale stays fixed", () => {
  const { control } = controller();
  control.pointer(touch("pointerdown", 1, 100, 100), origin);
  control.pointer(touch("pointermove", 1, 100, 160), origin);
  expect(control.view.x).toBe(0);
  expect(control.view.y).toBe(60);
  expect(control.view.scale).toBe(1);
});

test("the zoom stops at 800 %", () => {
  const { control } = controller();
  control.pointer(touch("pointerdown", 1, 0, 0), origin);
  control.pointer(touch("pointerdown", 2, 10, 0), origin);
  control.pointer(touch("pointermove", 2, 1000, 0), origin);
  expect(control.view.scale).toBe(MAX_SCALE);
});

test("a pen pointerdown ends the gesture", () => {
  const { control, views } = controller();
  control.pointer(touch("pointerdown", 1, 100, 100), origin);
  control.pointer(touch("pointerdown", 2, 200, 100), origin);
  const pen = new PointerEvent("pointerdown", { pointerId: 3, pointerType: "pen", clientX: 50, clientY: 50, buttons: 1 });
  expect(control.pointer(pen, origin)).toBe(false);
  control.pointer(touch("pointermove", 2, 300, 100), origin);
  expect(views).toEqual([]);
  expect(control.view.scale).toBe(1);
});
