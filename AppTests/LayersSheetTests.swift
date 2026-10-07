import XCTest
@testable import MathNotes

final class LayersSheetTests: XCTestCase {
  func testLayerActionLabelsNameTheirLayer() {
    XCTAssertEqual(layerActionAccessibilityLabel("Rename", layerName: "Proof"), "Rename Proof")
    XCTAssertEqual(layerActionAccessibilityLabel("Hide", layerName: "Proof"), "Hide Proof")
    XCTAssertEqual(layerActionAccessibilityLabel("Unlock", layerName: "Notes"), "Unlock Notes")
    XCTAssertEqual(layerActionAccessibilityLabel("Merge down", layerName: "Ink"), "Merge down Ink")
    XCTAssertEqual(layerActionAccessibilityLabel("Delete", layerName: "Ink"), "Delete Ink")
  }
  func testActiveLayerFallsBackWhenCurrentLayerBecomesHiddenOrLocked() {
    let ink = EngineLayer(id: "l-ink", name: "Ink", hidden: false, locked: false)
    let notes = EngineLayer(id: "l-notes", name: "Notes", hidden: false, locked: false)

    XCTAssertEqual(editableActiveLayerID(layers: [ink, notes], current: notes.id), notes.id)

    let hiddenNotes = EngineLayer(id: notes.id, name: notes.name, hidden: true, locked: false)
    XCTAssertEqual(editableActiveLayerID(layers: [ink, hiddenNotes], current: notes.id), ink.id)

    let lockedNotes = EngineLayer(id: notes.id, name: notes.name, hidden: false, locked: true)
    XCTAssertEqual(editableActiveLayerID(layers: [ink, lockedNotes], current: notes.id), ink.id)

    let lockedInk = EngineLayer(id: ink.id, name: ink.name, hidden: false, locked: true)
    XCTAssertNil(editableActiveLayerID(layers: [lockedInk, hiddenNotes], current: notes.id))
  }

  func testRemovedActiveLayerPrefersItsAdjacentFallback() {
    let ink = EngineLayer(id: "l-ink", name: "Ink", hidden: false, locked: false)
    let notes = EngineLayer(id: "l-notes", name: "Notes", hidden: false, locked: false)
    let top = EngineLayer(id: "l-top", name: "Top", hidden: false, locked: false)

    XCTAssertEqual(
      editableActiveLayerID(
        layers: [ink, notes],
        current: top.id,
        preferred: notes.id),
      notes.id)
    XCTAssertEqual(
      editableActiveLayerID(
        layers: [notes, top],
        current: ink.id,
        preferred: notes.id),
      notes.id)
  }

}
