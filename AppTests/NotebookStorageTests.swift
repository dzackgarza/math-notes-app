import CoreGraphics
import Foundation
import InkEngine
import UIKit
import XCTest
@testable import MathNotes

final class NotebookStorageTests: XCTestCase {
  @MainActor
  func testAppendPageUsesTheSharedDocumentAndBecomesDirty() throws {
    let document = EngineDocument(seed: 7)
    XCTAssertEqual(try document.pageCount(), 1)
    try document.markSaved()

    try document.appendPage()

    XCTAssertEqual(try document.pageCount(), 2)
    XCTAssertEqual(
      try document.dirtyFiles().map(\.path),
      ["notebook.json", "pages/0002.svg"])
  }

  @MainActor
  func testPageManagementUsesTheSharedDocumentHistory() throws {
    let document = EngineDocument(seed: 13)

    try document.insertPage(at: 0)
    XCTAssertEqual(try document.pageCount(), 2)

    try document.duplicatePage(at: 0)
    XCTAssertEqual(try document.pageCount(), 3)

    try document.deletePage(at: 1)
    XCTAssertEqual(try document.pageCount(), 2)

    XCTAssertNotNil(try document.undo())
    XCTAssertEqual(try document.pageCount(), 3)
  }

  @MainActor
  func testPageMoveUsesSharedOrderAndGeometry() throws {
    let document = EngineDocument(seed: 43)
    try document.appendPage()
    try document.appendPage()

    let first = try document.pageRect(index: 0)
    let second = try document.pageRect(index: 1)
    XCTAssertGreaterThan(second.minY, first.minY)

    try document.markSaved()
    try document.movePage(from: 0, to: 2)

    let changes = try document.dirtyFiles()
    XCTAssertEqual(changes.map(\.path), ["notebook.json"])
    let indexChange = try XCTUnwrap(changes.first)
    guard case let .write(indexBytes) = indexChange.kind else {
      return XCTFail("The reordered notebook index was not writable data")
    }
    let index = try XCTUnwrap(
      JSONSerialization.jsonObject(with: indexBytes) as? [String: Any])
    let pages = try XCTUnwrap(index["pages"] as? [[String: Any]])
    XCTAssertEqual(
      pages.compactMap { $0["file"] as? String },
      ["pages/0002.svg", "pages/0003.svg", "pages/0001.svg"])
  }


  @MainActor
  func testPageArrangementsUseSharedLayoutWithoutDirtyingTheNotebook() throws {
    let document = EngineDocument(seed: 47)
    try document.appendPage()
    try document.appendPage()
    try document.markSaved()

    try document.setArrangement(INK_PAGES_VERTICAL)
    let vertical0 = try document.pageRect(index: 0)
    let vertical1 = try document.pageRect(index: 1)
    XCTAssertGreaterThan(vertical1.minY, vertical0.minY)

    try document.setArrangement(INK_PAGES_HORIZONTAL)
    let horizontal0 = try document.pageRect(index: 0)
    let horizontal1 = try document.pageRect(index: 1)
    XCTAssertEqual(horizontal1.minY, horizontal0.minY, accuracy: 0.001)
    XCTAssertGreaterThan(horizontal1.minX, horizontal0.minX)

    try document.setArrangement(INK_PAGES_TWO_PAGE)
    let two0 = try document.pageRect(index: 0)
    let two1 = try document.pageRect(index: 1)
    let two2 = try document.pageRect(index: 2)
    XCTAssertEqual(two1.minY, two0.minY, accuracy: 0.001)
    XCTAssertGreaterThan(two1.minX, two0.minX)
    XCTAssertGreaterThan(two2.minY, two0.minY)

    XCTAssertTrue(try document.dirtyFiles().isEmpty)
  }
  @MainActor
  func testPDFExportUsesTheSharedDocument() throws {
    let document = EngineDocument(seed: 17)

    let pdf = try document.exportPDF(title: "Export Test")

    XCTAssertGreaterThan(pdf.count, 5)
    XCTAssertEqual(String(decoding: pdf.prefix(5), as: UTF8.self), "%PDF-")
  }


  @MainActor
  func testPDFExportRangeUsesTheSharedSpec() throws {
    let document = EngineDocument(seed: 53)
    try document.appendPage()
    try document.appendPage()

    let expected = try document.pageRect(index: 1)
    let pdf = try document.exportPDF(title: "Range Export", firstPage: 1, pageCount: 1)
    let provider = try XCTUnwrap(CGDataProvider(data: pdf as CFData))
    let exported = try XCTUnwrap(CGPDFDocument(provider))
    let page = try XCTUnwrap(exported.page(at: 1))
    let media = page.getBoxRect(.mediaBox)

    XCTAssertEqual(exported.numberOfPages, 1)
    // SkPDF rounds the page device to integer points before writing MediaBox.
    XCTAssertEqual(media.width, expected.width.rounded(), accuracy: 0.01)
    XCTAssertEqual(media.height, expected.height.rounded(), accuracy: 0.01)
  }

  @MainActor
  func testPDFImportRasterKeepsThePDFPageSizeInTheSharedDocument() throws {
    let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
    let pdf = UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
      context.beginPage()
      UIColor.black.setFill()
      context.cgContext.fill(CGRect(x: 0, y: 0, width: 306, height: 28.35))
    }
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("pdf")
    try pdf.write(to: url, options: .atomic)
    defer { try? FileManager.default.removeItem(at: url) }

    let imported = try PDFImportDocument(url: url)
    XCTAssertEqual(imported.pageCount, 1)
    let page = try imported.rasterizedPage(at: 0, maxWidthPixels: 256)

    let document = EngineDocument(seed: 59)
    try document.importPageImage(
      at: 0,
      png: page.png,
      widthPt: page.widthPt,
      heightPt: page.heightPt)
    try document.deletePage(at: 1)

    XCTAssertEqual(try document.pageCount(), 1)
    let rect = try document.pageRect(index: 0)
    XCTAssertEqual(rect.width, 612, accuracy: 0.01)
    XCTAssertEqual(rect.height, 792, accuracy: 0.01)
    XCTAssertTrue(
      try document.dirtyFiles().contains {
        $0.path.hasPrefix("assets/") && $0.path.hasSuffix(".png")
      })
  }

  @MainActor
  func testBuiltinTemplateFactoryMatchesTheSharedCreationPath() throws {
    XCTAssertEqual(
      try EngineDocument.builtinTemplateNames(),
      [
        "blank",
        "lined-wide",
        "lined-medium",
        "lined-narrow",
        "grid-coarse",
        "grid-medium",
        "grid-fine",
        "dotted",
      ])

    let template = try EngineDocument.builtinTemplate(name: "dotted", seed: 23)
    let templateChanges = try template.dirtyFiles()
    let pageChange = try XCTUnwrap(
      templateChanges.first { $0.path == "pages/0001.svg" })
    guard case let .write(page) = pageChange.kind else {
      return XCTFail("The built-in template page was not writable data")
    }

    let note = try EngineDocument.createFromTemplate(
      seed: 29,
      name: "dotted",
      page: page,
      pageSize: INK_PAGE_A4,
      orientation: INK_PORTRAIT)
    let noteIndex = try XCTUnwrap(
      try note.dirtyFiles().first { $0.path == "notebook.json" })
    guard case let .write(indexBytes) = noteIndex.kind else {
      return XCTFail("The new notebook index was not writable data")
    }
    let index = try XCTUnwrap(
      JSONSerialization.jsonObject(with: indexBytes) as? [String: Any])
    XCTAssertEqual(index["template"] as? String, "dotted")
    XCTAssertEqual(index["pageSize"] as? String, "A4")
  }

  @MainActor
  func testPageSizeSettingUsesTheSharedDocument() throws {
    let document = EngineDocument(seed: 31)

    try document.setPageSize(INK_PAGE_LETTER, orientation: INK_LANDSCAPE)
    let setting = try document.pageSize()

    XCTAssertEqual(setting.size, INK_PAGE_LETTER)
    XCTAssertEqual(setting.orientation, INK_LANDSCAPE)
    XCTAssertEqual(setting.width, 792, accuracy: 0.001)
    XCTAssertEqual(setting.height, 612, accuracy: 0.001)
  }

  @MainActor
  func testTemplateSettingUpdatesNotebookMetadata() throws {
    let template = try EngineDocument.builtinTemplate(name: "grid-medium", seed: 37)
    let templatePage = try XCTUnwrap(
      try template.dirtyFiles().first { $0.path == "pages/0001.svg" })
    guard case let .write(page) = templatePage.kind else {
      return XCTFail("The built-in template page was not writable data")
    }

    let document = EngineDocument(seed: 41)
    try document.setTemplate(name: "grid-medium", page: page)

    let indexChange = try XCTUnwrap(
      try document.dirtyFiles().first { $0.path == "notebook.json" })
    guard case let .write(indexBytes) = indexChange.kind else {
      return XCTFail("The notebook index was not writable data")
    }
    let index = try XCTUnwrap(
      JSONSerialization.jsonObject(with: indexBytes) as? [String: Any])
    XCTAssertEqual(index["template"] as? String, "grid-medium")
  }

  func testLibraryNameValidationMatchesTheWebRules() throws {
    XCTAssertEqual(try validatedLibraryName("  Stable pairs  "), "Stable pairs")
    XCTAssertThrowsError(try validatedLibraryName(""))
    XCTAssertThrowsError(try validatedLibraryName(".trash"))
    XCTAssertThrowsError(try validatedLibraryName("A/B"))
    XCTAssertThrowsError(try validatedLibraryName("A\\B"))
  }

  func testLibraryFavoriteMetadataPersistsAndFollowsMoves() throws {
    let original = Data(
      """
      {
        "format": "math-notes-library",
        "version": 1,
        "tags": [{ "name": "Research", "color": "#2F6FEB" }],
        "notes": {
          "Analysis/Integrals": {
            "favorite": false,
            "tags": ["Research"],
            "description": "Measure theory"
          }
        },
        "folders": {
          "Analysis": {
            "description": "Analysis notes",
            "paper": "grid-medium",
            "coverColor": "#24324A",
            "coverStyle": "spine",
            "tags": ["Research"]
          }
        },
        "startingTemplates": [{
          "name": "Seminar notes",
          "folder": ["Analysis"],
          "paper": "grid-medium",
          "pageSize": "letter",
          "tags": ["Research"]
        }],
        "draft": {
          "folder": ["Analysis"],
          "title": "Derived categories",
          "template": "grid-medium",
          "tags": ["Research"],
          "pageSize": "letter"
        }
      }
      """.utf8)

    let favored = try LibraryMetadataFile.settingFavorite(
      in: original,
      path: ["Analysis", "Integrals"],
      favorite: true)
    XCTAssertEqual(
      try LibraryMetadataFile.favoritePaths(in: favored),
      Set(["Analysis/Integrals"]))

    let moved = try XCTUnwrap(
      LibraryMetadataFile.moving(
        in: favored,
        from: ["Analysis"],
        to: ["Real analysis"]))
    XCTAssertEqual(
      try LibraryMetadataFile.favoritePaths(in: moved),
      Set(["Real analysis/Integrals"]))

    let root = try XCTUnwrap(
      JSONSerialization.jsonObject(with: moved) as? [String: Any])
    let notes = try XCTUnwrap(root["notes"] as? [String: Any])
    let note = try XCTUnwrap(notes["Real analysis/Integrals"] as? [String: Any])
    XCTAssertEqual(note["tags"] as? [String], ["Research"])
    XCTAssertEqual(note["description"] as? String, "Measure theory")
    XCTAssertNil(notes["Analysis/Integrals"])

    let folders = try XCTUnwrap(root["folders"] as? [String: Any])
    XCTAssertNotNil(folders["Real analysis"])
    XCTAssertNil(folders["Analysis"])

    let templates = try XCTUnwrap(root["startingTemplates"] as? [[String: Any]])
    XCTAssertEqual(templates.first?["folder"] as? [String], ["Real analysis"])
    let draft = try XCTUnwrap(root["draft"] as? [String: Any])
    XCTAssertEqual(draft["folder"] as? [String], ["Real analysis"])
  }

  func testLibraryMetadataFollowsTrashAndRestore() throws {
    let original = Data(
      """
      {
        "format": "math-notes-library",
        "version": 1,
        "tags": [],
        "notes": {
          "Inbox/Movable": {
            "favorite": true,
            "tags": ["algebra"],
            "description": "Moved from Inbox"
          }
        },
        "folders": {},
        "startingTemplates": []
      }
      """.utf8)

    let trashed = try XCTUnwrap(
      LibraryMetadataFile.moving(
        in: original,
        from: ["Inbox", "Movable"],
        to: [".trash", "Movable"]))
    XCTAssertEqual(
      try LibraryMetadataFile.favoritePaths(in: trashed),
      Set([".trash/Movable"]))

    let restored = try XCTUnwrap(
      LibraryMetadataFile.moving(
        in: trashed,
        from: [".trash", "Movable"],
        to: ["Archive", "Movable"]))
    XCTAssertEqual(
      try LibraryMetadataFile.favoritePaths(in: restored),
      Set(["Archive/Movable"]))

    let root = try XCTUnwrap(
      JSONSerialization.jsonObject(with: restored) as? [String: Any])
    let notes = try XCTUnwrap(root["notes"] as? [String: Any])
    let note = try XCTUnwrap(notes["Archive/Movable"] as? [String: Any])
    XCTAssertEqual(note["tags"] as? [String], ["algebra"])
    XCTAssertEqual(note["description"] as? String, "Moved from Inbox")
    XCTAssertNil(notes["Inbox/Movable"])
    XCTAssertNil(notes[".trash/Movable"])
  }

  func testLibraryMetadataUsesCanonicalFormatOrder() throws {
    let data = try LibraryMetadataFile.settingFavorite(
      in: nil,
      path: ["Analysis", "Integrals"],
      favorite: true)

    XCTAssertEqual(
      String(decoding: data, as: UTF8.self),
      """
      {
        "format": "math-notes-library",
        "version": 1,
        "tags": [],
        "notes": {
          "Analysis/Integrals": {
            "favorite": true,
            "tags": [],
            "description": ""
          }
        },
        "folders": {},
        "startingTemplates": []
      }

      """)
  }

  func testLibraryDetailsPersistAndRegisterUnknownTags() throws {
    let original = Data(
      """
      {
        "format": "math-notes-library",
        "version": 1,
        "tags": [
          { "name": "Research", "color": "#2F6FEB" }
        ],
        "notes": {
          "Analysis/Integrals": {
            "favorite": true,
            "tags": ["Research"],
            "description": "Old description"
          }
        },
        "folders": {},
        "startingTemplates": []
      }
      """.utf8)

    let noteData = try LibraryMetadataFile.settingNoteDetails(
      in: original,
      path: ["Analysis", "Integrals"],
      details: LibraryNoteDetails(
        favorite: true,
        tags: ["Research", "Seminar", "Seminar", "  "],
        description: "Measure theory"))
    XCTAssertEqual(
      try LibraryMetadataFile.noteDetails(
        in: noteData,
        path: ["Analysis", "Integrals"]),
      LibraryNoteDetails(
        favorite: true,
        tags: ["Research", "Seminar"],
        description: "Measure theory"))
    XCTAssertEqual(
      try LibraryMetadataFile.tags(in: noteData),
      [
        LibraryTag(name: "Research", color: "#2F6FEB"),
        LibraryTag(name: "Seminar", color: "#3FA35B"),
      ])

    let folderData = try LibraryMetadataFile.settingFolderDetails(
      in: noteData,
      path: ["Analysis"],
      details: LibraryFolderDetails(
        description: "Analysis notes",
        paper: "grid-medium",
        coverColor: "#24324A",
        coverStyle: "spine",
        tags: ["Seminar", "Reading"])))
    XCTAssertEqual(
      try LibraryMetadataFile.folderDetails(in: folderData, path: ["Analysis"]),
      LibraryFolderDetails(
        description: "Analysis notes",
        paper: "grid-medium",
        coverColor: "#24324A",
        coverStyle: "spine",
        tags: ["Seminar", "Reading"]))
    XCTAssertEqual(
      try LibraryMetadataFile.tags(in: folderData).last,
      LibraryTag(name: "Reading", color: "#8B5CF6"))
  }

  func testWritesAssetsThenPagesThenNotebookMetadataThenDeletes() {
    let changes = [
      EngineFileChange(path: "pages/0002.svg", kind: .delete),
      EngineFileChange(path: "notebook.json", kind: .write(Data("index".utf8))),
      EngineFileChange(path: "pages/0001.svg", kind: .write(Data("page".utf8))),
      EngineFileChange(path: "assets/diagram.png", kind: .write(Data([1, 2, 3]))),
      EngineFileChange(path: "assets/old.png", kind: .delete),
    ]

    XCTAssertEqual(
      orderedNotebookChanges(changes).map(\.path),
      [
        "assets/diagram.png",
        "pages/0001.svg",
        "notebook.json",
        "assets/old.png",
        "pages/0002.svg",
      ])
  }
}
