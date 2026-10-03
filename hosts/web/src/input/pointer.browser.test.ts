// The pointer adapter on constructed PointerEvents, in Chromium (vitest.config.ts).
import { describe, expect, test } from "vitest";

import { Has, Phase, Tool } from "../engine/engine.ts";
import { capabilities, penSamples } from "./pointer.ts";

const origin = { x: 10, y: 20 };
const pen = capabilities("pen");

function event(type: string, init: PointerEventInit): PointerEvent {
  return new PointerEvent(type, { pointerId: 1, pointerType: "pen", isPrimary: true, ...init });
}

describe("penSamples", () => {
  test("a pen sample carries pressure, the tilt angles and twist in radians", () => {
    const e = event("pointermove", {
      clientX: 110,
      clientY: 70,
      buttons: 1,
      pressure: 0.625,
      tiltX: 30,
      tiltY: 0,
      twist: 90,
    });
    const [s] = penSamples(e, origin, pen, { next: 7 });
    expect(s).toMatchObject({ x: 100, y: 50, pressure: 0.625, buttons: 1, id: 7 });
    // Chrome computes the angles from the tilts: a 30 degree tilt toward +x.
    expect(s.altitude).toBeCloseTo((60 * Math.PI) / 180, 6);
    expect(s.azimuth).toBeCloseTo(0, 6);
    expect(s.roll).toBeCloseTo(Math.PI / 2, 6);
    expect(s).toMatchObject({ tool: Tool.pen, phase: Phase.move, predicted: false, has: pen });
  });

  test("a move without buttons is hover", () => {
    const [s] = penSamples(event("pointermove", { buttons: 0 }), origin, pen, { next: 0 });
    expect(s.phase).toBe(Phase.hover);
  });

  test("the eraser end is the eraser tool, down and up", () => {
    const down = penSamples(event("pointerdown", { button: 5, buttons: 32 }), origin, pen, { next: 0 });
    const up = penSamples(event("pointerup", { button: 5, buttons: 0 }), origin, pen, { next: 1 });
    expect(down).toMatchObject([{ tool: Tool.eraser, phase: Phase.begin }]);
    expect(up).toMatchObject([{ tool: Tool.eraser, phase: Phase.end }]);
  });

  test("a stroke begun with the side button held erases until the pen lifts", () => {
    const ids = { next: 0 };
    const down = penSamples(event("pointerdown", { button: 0, buttons: 3 }), origin, pen, ids);
    const released = penSamples(event("pointermove", { buttons: 1 }), origin, pen, ids);
    const up = penSamples(event("pointerup", { button: 0, buttons: 0 }), origin, pen, ids);
    expect([...down, ...released, ...up]).toMatchObject([
      { tool: Tool.eraser, phase: Phase.begin },
      { tool: Tool.eraser, phase: Phase.move },
      { tool: Tool.eraser, phase: Phase.end },
    ]);
    const next = penSamples(event("pointerdown", { button: 0, buttons: 1 }), origin, pen, ids);
    expect(next).toMatchObject([{ tool: Tool.pen, phase: Phase.begin }]);
  });

  test("a finger is the pen when fingers draw, and the touch tool otherwise", () => {
    const finger = (type: string) =>
      new PointerEvent(type, { pointerId: 2, pointerType: "touch", isPrimary: true, buttons: 1 });
    const ids = { next: 0 };
    expect(penSamples(finger("pointerdown"), origin, 0, ids, true)).toMatchObject([{ tool: Tool.pen }]);
    expect(penSamples(finger("pointerup"), origin, 0, ids, true)).toMatchObject([{ tool: Tool.pen }]);
    expect(penSamples(finger("pointerdown"), origin, 0, ids)).toMatchObject([{ tool: Tool.touch }]);
  });

  test("coalesced samples come first in order, then the predicted ones flagged", () => {
    const at = (x: number) => new PointerEvent("pointermove", { pointerType: "pen", clientX: x, clientY: 20, buttons: 1 });
    const e = event("pointermove", {
      clientX: 40,
      clientY: 20,
      buttons: 1,
      coalescedEvents: [at(20), at(30), at(40)],
      predictedEvents: [at(50)],
    });
    const ids = { next: 0 };
    const samples = penSamples(e, origin, pen, ids);
    expect(samples).toMatchObject([
      { x: 10, predicted: false, id: 0 },
      { x: 20, predicted: false, id: 1 },
      { x: 30, predicted: false, id: 2 },
      { x: 40, predicted: true, id: 3 },
    ]);
    expect(ids.next).toBe(4);
  });

  test("an event without a coalesced list is its own sample", () => {
    const samples = penSamples(event("pointerdown", { clientX: 15, clientY: 25, buttons: 1 }), origin, pen, { next: 0 });
    expect(samples).toMatchObject([{ x: 5, y: 5, phase: Phase.begin }]);
  });
});

describe("capabilities", () => {
  test("come from the pointer type, not from values", () => {
    expect(capabilities("pen")).toBe(Has.pressure | Has.altitude | Has.azimuth | Has.roll);
    expect(capabilities("mouse")).toBe(0);
    expect(capabilities("touch")).toBe(0);
  });
});
