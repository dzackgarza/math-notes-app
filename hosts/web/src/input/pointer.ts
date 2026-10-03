// PointerEvent -> InkPenSample records: one batch per event, the coalesced
// samples (or the event itself when the list is empty), then the predicted
// ones flagged. Follows W3C Pointer Events Level 3, §"Coalesced and
// predicted events" and its drawing example.
import { Has, Phase, Tool, type PenSample } from "../engine/engine.ts";

// INK_HAS_* bits: what Chrome measures for a pointer type. The values say
// nothing: Chrome reports pressure 0.5 and twist 0 without a sensor.
export function capabilities(pointerType: string): number {
  return pointerType === "pen" ? Has.pressure | Has.altitude | Has.azimuth | Has.roll : 0;
}

// Numbers each sample; `ink_input_update` refers to samples by id.
export interface SampleIds {
  next: number;
}

const ERASER_BUTTON = 5; // PointerEvent.button of the pen's eraser end
const ERASER_BUTTONS = 32; // its bit in PointerEvent.buttons
const BARREL_BUTTON = 2; // PointerEvent.button of the pen's side (barrel) button
const BARREL_BUTTONS = 2; // its bit in PointerEvent.buttons

// The tool of each pointer that is down, chosen at pointerdown. The side
// button is released or the pen lifts with buttons 0, and the rest of the
// stroke must still reach the gesture that its first sample started.
const downTools = new Map<number, number>();

function phase(e: PointerEvent): number {
  switch (e.type) {
    case "pointerdown":
      return Phase.begin;
    case "pointerup":
      return Phase.end;
    case "pointercancel":
      return Phase.cancel;
    default:
      return e.buttons === 0 ? Phase.hover : Phase.move;
  }
}

function buttonTool(e: PointerEvent, fingerDraws: boolean): number {
  if (e.pointerType === "touch") return fingerDraws ? Tool.pen : Tool.touch;
  if (e.pointerType === "mouse") return Tool.mouse;
  const eraser =
    (e.buttons & (ERASER_BUTTONS | BARREL_BUTTONS)) !== 0 ||
    e.button === ERASER_BUTTON ||
    e.button === BARREL_BUTTON;
  return eraser ? Tool.eraser : Tool.pen;
}

function tool(e: PointerEvent, eventPhase: number, fingerDraws: boolean): number {
  if (eventPhase === Phase.begin) downTools.set(e.pointerId, buttonTool(e, fingerDraws));
  const kind = downTools.get(e.pointerId) ?? buttonTool(e, fingerDraws);
  if (eventPhase === Phase.end || eventPhase === Phase.cancel) downTools.delete(e.pointerId);
  return kind;
}

// `origin` is the canvas's top-left in client coordinates (CSS px).
// `fingerDraws` makes a touch the pen tool instead of the touch tool.
export function penSamples(
  e: PointerEvent,
  origin: { x: number; y: number },
  has: number,
  ids: SampleIds,
  fingerDraws = false,
): PenSample[] {
  const eventPhase = phase(e);
  const kind = tool(e, eventPhase, fingerDraws);
  const sample = (p: PointerEvent, samplePhase: number, predicted: boolean): PenSample => {
    return {
      x: p.clientX - origin.x,
      y: p.clientY - origin.y,
      time: p.timeStamp,
      pressure: p.pressure,
      altitude: p.altitudeAngle,
      azimuth: p.azimuthAngle,
      roll: (p.twist * Math.PI) / 180,
      hoverHeight: 0,
      buttons: p.buttons,
      has,
      id: ids.next++,
      tool: kind,
      phase: samplePhase,
      predicted,
    };
  };
  const coalesced = e.getCoalescedEvents?.() ?? [];
  const real = coalesced.length > 0 ? coalesced : [e];
  // Begin marks the first sample of the stroke; end and cancel the last.
  const samples = real.map((p, i) => {
    if (eventPhase === Phase.begin) return sample(p, i === 0 ? Phase.begin : Phase.move, false);
    if (eventPhase === Phase.end || eventPhase === Phase.cancel) {
      return sample(p, i === real.length - 1 ? eventPhase : Phase.move, false);
    }
    return sample(p, eventPhase, false);
  });
  if (eventPhase === Phase.move) {
    for (const p of e.getPredictedEvents?.() ?? []) samples.push(sample(p, Phase.move, true));
  }
  return samples;
}
