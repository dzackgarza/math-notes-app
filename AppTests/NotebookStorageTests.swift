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
  func testLayerManagementUsesSharedDocumentState() throws {
    let document = EngineDocument(seed: 67)
    XCTAssertEqual(try document.layers().map(\.name), ["Ink"])

    try document.addLayer(name: "Annotations")
    var layers = try document.layers()
    XCTAssertEqual(layers.map(\.name), ["Ink", "Annotations"])
    let annotationsID = layers[1].id

    XCTAssertNotNil(try document.undo())
    XCTAssertEqual(try document.layers().map(\.name), ["Ink"])
    XCTAssertNotNil(try document.redo())
    layers = try document.layers()
    XCTAssertEqual(layers.map(\.name), ["Ink", "Annotations"])
    XCTAssertEqual(layers[1].id, annotationsID)

    try document.setLayer(
      index: 1,
      name: "Hidden annotations",
      hidden: true,
      locked: false)
    layers = try document.layers()
    XCTAssertEqual(layers[1].id, annotationsID)
    XCTAssertTrue(layers[1].hidden)

    try document.moveLayer(from: 1, to: 0)
    layers = try document.layers()
    XCTAssertEqual(layers[0].id, annotationsID)
    XCTAssertEqual(layers.map(\.name), ["Hidden annotations", "Ink"])

    try document.removeLayer(index: 0, mergeDown: false)
    XCTAssertEqual(try document.layers().map(\.name), ["Ink"])
    XCTAssertFalse(try document.dirtyFiles().isEmpty)
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
  func testPDFExportCanSelectLayers() throws {
    let document = EngineDocument(seed: 71)
    try document.addLayer(name: "Annotations")
    let layers = try document.layers()
    XCTAssertEqual(layers.count, 2)

    let pdf = try document.exportPDF(
      title: "Layer Export",
      layerIDs: [layers[1].id])

    XCTAssertGreaterThan(pdf.count, 5)
    XCTAssertEqual(String(decoding: pdf.prefix(5), as: UTF8.self), "%PDF-")
  }

  @MainActor
  func testNavigationAndBookmarkPreviewUseSharedDocumentData() throws {
    let repository = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let fixture = repository
      .appendingPathComponent("core/tests/fixtures/documents/full", isDirectory: true)
    let document = EngineDocument(seed: 73)
    try document.loadNotebook(
      Data(contentsOf: fixture.appendingPathComponent("notebook.json")))
    try document.loadPage(
      path: "pages/0002.svg",
      data: Data(contentsOf: fixture.appendingPathComponent("pages/0002.svg")))

    let destinations = try document.navigation().filter { $0.href.isEmpty }
    XCTAssertEqual(destinations.filter { $0.id.isEmpty }.count, 4)
    let bookmark = try XCTUnwrap(
      destinations.first { $0.id == "b-bookmark0001" })
    XCTAssertEqual(bookmark.page, 1)
    XCTAssertEqual(try XCTUnwrap(bookmark.x), 79.2, accuracy: 0.01)

    let preview = try document.bookmarkPNG(id: bookmark.id, width: 240)
    XCTAssertGreaterThan(preview.count, 8)
    XCTAssertEqual(Array(preview.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
  }


  @MainActor
  func testClippingRoundTripUsesSharedDocumentFormat() throws {
    let document = EngineDocument(seed: 79)
    try document.deletePage(at: 0)
    try document.addClipping(
      svg: "<svg xmlns=\"http://www.w3.org/2000/svg\"><g><rect x=\"10\" y=\"20\" width=\"30\" height=\"40\" fill=\"none\" stroke=\"#000000\"/></g></svg>")

    XCTAssertEqual(try document.pageCount(), 1)
    let svg = try document.clippingSVG(index: 0)
    XCTAssertTrue(svg.contains("<rect"))
    let png = try document.pagePNG(index: 0, width: 120)
    XCTAssertEqual(Array(png.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
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

  func testConflictProviderNamesMatchTheFormatContract() {
    let cases: [(String, String)] = [
      ("0007 (Zack's conflicted copy 2026-10-02).svg", "Dropbox"),
      ("0007 (conflicted copy Zack 2026-10-02 143000).svg", "Nextcloud"),
      ("0007 (case clash from Zack).svg", "Nextcloud"),
      ("0007.sync-conflict-20261002-143000-abcdef0.svg", "Syncthing"),
      ("0007 2.svg", "iCloud Drive"),
      ("0007-iPad.svg", "OneDrive"),
      ("0007 (1).svg", "Google Drive"),
      ("0007 copy.svg", "Unlisted version"),
    ]

    for (name, provider) in cases {
      XCTAssertEqual(notebookConflictProvider(name), provider, name)
    }
  }

  func testConflictCandidatesDetectProviderCopiesAndUnlistedPages() {
    let candidates = notebookConflictCandidates(
      listedPages: ["pages/0007.svg"],
      rootFiles: ["notebook.json", "notebook (1).json"],
      pageFiles: [
        "0007.svg",
        "0007 (Zack's conflicted copy 2026-10-02).svg",
        "0007.sync-conflict-20261002-143000-abcdef0.svg",
        "0007 odd copy.svg",
      ],
      assetFiles: [
        "photo.png",
        "photo (math-notes conflict 2026-10-02 UUID).png",
      ])

    XCTAssertEqual(candidates.count, 5)
    XCTAssertTrue(candidates.contains {
      $0.original == "pages/0007.svg" &&
        $0.provider == "Dropbox"
    })
    XCTAssertTrue(candidates.contains {
      $0.original == "pages/0007.svg" &&
        $0.provider == "Syncthing"
    })
    XCTAssertTrue(candidates.contains {
      $0.original == "pages/0007.svg" &&
        $0.provider == "Unlisted version"
    })
    XCTAssertTrue(candidates.contains {
      $0.original == "notebook.json" &&
        $0.copy == "notebook (1).json"
    })
    XCTAssertTrue(candidates.contains {
      $0.original == "assets/photo.png" &&
        $0.provider == "Math Notes"
    })
  }

  @MainActor
  func testConflictFixtureDetectsEveryProviderUnlistedPageAndNotebookConflict() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let root = NotesRootAccess(testURL: directory)
    let (reference, _) = try root.createNote(
      title: "Conflict fixture",
      parent: FolderReference(path: []),
      template: "blank",
      pageSize: INK_PAGE_A4,
      orientation: INK_PORTRAIT)
    let noteURL = directory.appendingPathComponent(reference.name, isDirectory: true)
    let pagesURL = noteURL.appendingPathComponent("pages", isDirectory: true)
    let page = try Data(contentsOf: pagesURL.appendingPathComponent("0001.svg"))
    let pageCopies: [(String, String)] = [
      ("0001 (Zack's conflicted copy 2026-10-02).svg", "Dropbox"),
      ("0001 (conflicted copy Zack 2026-10-02 143000).svg", "Nextcloud"),
      ("0001 (case clash from Zack).svg", "Nextcloud"),
      ("0001.sync-conflict-20261002-143000-abcdef0.svg", "Syncthing"),
      ("0001 2.svg", "iCloud Drive"),
      ("0001-iPad.svg", "OneDrive"),
      ("0001 (1).svg", "Google Drive"),
      ("0001 odd copy.svg", "Unlisted version"),
    ]
    for (name, _) in pageCopies {
      try page.write(to: pagesURL.appendingPathComponent(name))
    }
    let notebook = try Data(contentsOf: noteURL.appendingPathComponent("notebook.json"))
    try notebook.write(to: noteURL.appendingPathComponent("notebook (1).json"))

    let conflicts = try root.conflicts(reference)
    var providersByCopy: [String: String] = [:]
    for conflict in conflicts {
      if case let .namedCopy(path) = conflict.source {
        providersByCopy[path] = conflict.provider
      }
    }

    XCTAssertEqual(conflicts.count, 9)
    for (name, provider) in pageCopies {
      XCTAssertEqual(providersByCopy["pages/\(name)"], provider, name)
    }
    XCTAssertEqual(providersByCopy["notebook (1).json"], "Google Drive")
    XCTAssertEqual(conflicts.first { $0.original == "notebook.json" }?.notebook, true)
  }

  func testSaveComparisonOnlyFlagsBytesChangedOutsideMathNotes() {
    let base = Data([1, 2, 3])
    let local = Data([4, 5, 6])
    let external = Data([7, 8, 9])

    XCTAssertFalse(
      notebookFileHasExternalChange(
        current: base, base: base, target: local))
    XCTAssertFalse(
      notebookFileHasExternalChange(
        current: local, base: base, target: local))
    XCTAssertTrue(
      notebookFileHasExternalChange(
        current: external, base: base, target: local))
    XCTAssertTrue(
      notebookFileHasExternalChange(
        current: nil, base: base, target: local))
  }

  @MainActor
  func testImportPageSVGProvidesTheKeepBothPrimitive() throws {
    let source = EngineDocument(seed: 83)
    let pageChange = try XCTUnwrap(
      try source.dirtyFiles().first { $0.path == "pages/0001.svg" })
    guard case let .write(pageBytes) = pageChange.kind else {
      return XCTFail("The source page was not writable data")
    }

    let document = EngineDocument(seed: 89)
    try document.markSaved()
    try document.importPageSVG(at: 1, data: pageBytes)

    XCTAssertEqual(try document.pageCount(), 2)
    let dirty = try document.dirtyFiles().map(\.path)
    XCTAssertTrue(dirty.contains("notebook.json"))
    XCTAssertTrue(dirty.contains("pages/0002.svg"))
  }

  @MainActor
  func testExternalEditSavePreservesOriginalAndWritesMathNotesConflictCopy() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let root = NotesRootAccess(testURL: directory)
    let (reference, document) = try root.createNote(
      title: "External edit",
      parent: FolderReference(path: []),
      template: "blank",
      pageSize: INK_PAGE_A4,
      orientation: INK_PORTRAIT)
    let notebookURL = directory
      .appendingPathComponent(reference.name, isDirectory: true)
      .appendingPathComponent("notebook.json")
    let base = try Data(contentsOf: notebookURL)

    try document.setPageSize(INK_PAGE_LETTER, orientation: INK_PORTRAIT)
    let outgoingChange = try XCTUnwrap(
      try document.dirtyFiles().first { $0.path == "notebook.json" })
    guard case let .write(outgoing) = outgoingChange.kind else {
      return XCTFail("The local notebook change did not produce writable bytes")
    }

    var external = base
    external.append(contentsOf: " ".utf8)
    try external.write(to: notebookURL, options: .atomic)

    XCTAssertThrowsError(try root.save(document, notebook: reference)) { error in
      guard case NotebookStorageError.externalChanges(let paths) = error else {
        return XCTFail("Unexpected error: \(error)")
      }
      XCTAssertEqual(paths, ["notebook.json"])
    }
    XCTAssertEqual(try Data(contentsOf: notebookURL), external)

    let notebookDirectory = notebookURL.deletingLastPathComponent()
    let copies = try FileManager.default.contentsOfDirectory(atPath: notebookDirectory.path)
      .filter {
        $0.hasPrefix("notebook (math-notes conflict ") && $0.hasSuffix(".json")
      }
    XCTAssertEqual(copies.count, 1)
    let copyURL = notebookDirectory.appendingPathComponent(try XCTUnwrap(copies.first))
    XCTAssertEqual(try Data(contentsOf: copyURL), outgoing)
  }

  @MainActor
  func testExternalPageEditWritesMathNotesConflictCopyWithoutReplacingExternalBytes() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let root = NotesRootAccess(testURL: directory)
    let (reference, document) = try root.createNote(
      title: "Page external edit",
      parent: FolderReference(path: []),
      template: "blank",
      pageSize: INK_PAGE_A4,
      orientation: INK_PORTRAIT)
    let noteURL = directory.appendingPathComponent(reference.name, isDirectory: true)
    let pageURL = noteURL.appendingPathComponent("pages/0001.svg")
    let base = try Data(contentsOf: pageURL)

    let canvas = InkCanvasView(document: document)
    canvas.frame = CGRect(x: 0, y: 0, width: 1024, height: 1024)
    canvas.layoutIfNeeded()
    canvas.setViewTransform(.identity)
    let page = try document.pageRect(index: 0)
    try canvas.editText(
      EngineTextProperties(content: "local page edit", width: 144, rtl: false),
      at: CGPoint(x: page.minX + 72, y: page.minY + 72),
      existing: false)
    let localChange = try XCTUnwrap(
      try document.dirtyFiles().first { $0.path == "pages/0001.svg" })
    guard case let .write(localPage) = localChange.kind else {
      return XCTFail("The local page edit did not produce writable bytes")
    }
    XCTAssertNotEqual(localPage, base)

    var external = base
    external.append(0x20)
    try external.write(to: pageURL, options: .atomic)

    XCTAssertThrowsError(try root.save(document, notebook: reference)) { error in
      guard case NotebookStorageError.externalChanges(let paths) = error else {
        return XCTFail("Unexpected error: \(error)")
      }
      XCTAssertEqual(paths, ["pages/0001.svg"])
    }
    XCTAssertEqual(try Data(contentsOf: pageURL), external)

    let copies = try FileManager.default.contentsOfDirectory(
      atPath: pageURL.deletingLastPathComponent().path
    ).filter {
      $0.hasPrefix("0001 (math-notes conflict ") && $0.hasSuffix(".svg")
    }
    XCTAssertEqual(copies.count, 1)
    let copyURL = pageURL.deletingLastPathComponent()
      .appendingPathComponent(try XCTUnwrap(copies.first))
    XCTAssertEqual(try Data(contentsOf: copyURL), localPage)
    let conflict = try XCTUnwrap(
      try root.conflicts(reference).first { $0.provider == "Math Notes" })
    XCTAssertEqual(conflict.original, "pages/0001.svg")
  }

  @MainActor
  func testKeepBothConflictCreatesSecondPageAndDeletesConflictCopy() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let root = NotesRootAccess(testURL: directory)
    let (reference, _) = try root.createNote(
      title: "Keep both",
      parent: FolderReference(path: []),
      template: "blank",
      pageSize: INK_PAGE_A4,
      orientation: INK_PORTRAIT)
    let noteURL = directory.appendingPathComponent(reference.name, isDirectory: true)
    let pageURL = noteURL.appendingPathComponent("pages/0001.svg")
    let conflictURL = noteURL.appendingPathComponent("pages/0001 odd copy.svg")
    try Data(contentsOf: pageURL).write(to: conflictURL, options: .atomic)
    let sentinelURL = noteURL.appendingPathComponent("unrelated-sentinel.txt")
    let sentinel = Data("keep me".utf8)
    try sentinel.write(to: sentinelURL)

    let conflict = try XCTUnwrap(try root.conflicts(reference).first)
    XCTAssertTrue(conflict.page)
    XCTAssertEqual(conflict.provider, "Unlisted version")
    try root.resolveConflict(reference, conflict: conflict, choice: .both)

    XCTAssertFalse(FileManager.default.fileExists(atPath: conflictURL.path))
    XCTAssertEqual(try Data(contentsOf: sentinelURL), sentinel)
    XCTAssertEqual(try root.conflictCount(reference), 0)
    XCTAssertEqual(try root.load(reference).pageCount(), 2)
  }

  @MainActor
  func testExternalEditAgainstLocalPageDeletionCanKeepTheExternalPage() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let root = NotesRootAccess(testURL: directory)
    let (reference, document) = try root.createNote(
      title: "Delete conflict keep file",
      parent: FolderReference(path: []),
      template: "blank",
      pageSize: INK_PAGE_A4,
      orientation: INK_PORTRAIT)
    try document.insertPage(at: 1)
    try root.save(document, notebook: reference)

    let noteURL = directory.appendingPathComponent(reference.name, isDirectory: true)
    let pageURL = noteURL.appendingPathComponent("pages/0002.svg")
    var external = try Data(contentsOf: pageURL)
    external.append(0x20)
    try external.write(to: pageURL, options: .atomic)

    try document.deletePage(at: 1)
    XCTAssertThrowsError(try root.save(document, notebook: reference)) { error in
      guard case NotebookStorageError.externalChanges(let paths) = error else {
        return XCTFail("Unexpected error: \(error)")
      }
      XCTAssertEqual(paths, ["pages/0002.svg"])
    }

    let conflict = try XCTUnwrap(
      try root.conflicts(reference).first {
        $0.original == "pages/0002.svg" && $0.copyBytes == nil
      })
    XCTAssertTrue(conflict.page)
    XCTAssertEqual(conflict.rightSummary, "This file is deleted in Math Notes.")

    try root.resolveConflict(reference, conflict: conflict, choice: .original)

    XCTAssertEqual(try Data(contentsOf: pageURL), external)
    XCTAssertEqual(try root.conflictCount(reference), 0)
    XCTAssertEqual(try root.load(reference).pageCount(), 2)
  }

  @MainActor
  func testExternalEditAgainstLocalPageDeletionCanKeepTheDeletion() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let root = NotesRootAccess(testURL: directory)
    let (reference, document) = try root.createNote(
      title: "Delete conflict keep deletion",
      parent: FolderReference(path: []),
      template: "blank",
      pageSize: INK_PAGE_A4,
      orientation: INK_PORTRAIT)
    try document.insertPage(at: 1)
    try root.save(document, notebook: reference)

    let noteURL = directory.appendingPathComponent(reference.name, isDirectory: true)
    let pageURL = noteURL.appendingPathComponent("pages/0002.svg")
    var external = try Data(contentsOf: pageURL)
    external.append(0x20)
    try external.write(to: pageURL, options: .atomic)

    try document.deletePage(at: 1)
    XCTAssertThrowsError(try root.save(document, notebook: reference))

    let conflict = try XCTUnwrap(
      try root.conflicts(reference).first {
        $0.original == "pages/0002.svg" && $0.copyBytes == nil
      })
    try root.resolveConflict(reference, conflict: conflict, choice: .copy)

    XCTAssertFalse(FileManager.default.fileExists(atPath: pageURL.path))
    XCTAssertEqual(try root.conflictCount(reference), 0)
    XCTAssertEqual(try root.load(reference).pageCount(), 1)
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

  func testNewNoteDraftAndStartingTemplatesRoundTripAndRegisterTags() throws {
    let draft = NewNoteDraft(
      folder: ["Analysis"],
      title: "Derived categories",
      template: "grid-medium",
      tags: ["Research", "Seminar"],
      pageSize: "letter",
      orientation: "landscape")
    let draftData = try LibraryMetadataFile.settingNewNoteDraft(in: nil, draft: draft)
    XCTAssertEqual(try LibraryMetadataFile.newNoteDraft(in: draftData), draft)
    XCTAssertEqual(
      try LibraryMetadataFile.tags(in: draftData).map(\.name),
      ["Research", "Seminar"])

    let first = NewNoteStartingTemplate(
      name: "Lecture",
      folder: ["Analysis"],
      paper: "dotted",
      pageSize: "a4",
      orientation: nil,
      tags: ["Research"])
    let templateData = try LibraryMetadataFile.settingNewNoteStartingTemplate(
      in: draftData,
      template: first)
    XCTAssertEqual(try LibraryMetadataFile.newNoteDraft(in: templateData), draft)
    XCTAssertEqual(try LibraryMetadataFile.newNoteStartingTemplates(in: templateData), [first])

    let replacement = NewNoteStartingTemplate(
      name: "Lecture",
      folder: ["Courses"],
      paper: "lined-medium",
      pageSize: "letter",
      orientation: "portrait",
      tags: ["Reading"])
    let replaced = try LibraryMetadataFile.settingNewNoteStartingTemplate(
      in: templateData,
      template: replacement)
    XCTAssertEqual(try LibraryMetadataFile.newNoteStartingTemplates(in: replaced), [replacement])
    XCTAssertEqual(try LibraryMetadataFile.newNoteDraft(in: replaced), draft)
    XCTAssertEqual(
      try LibraryMetadataFile.tags(in: replaced).map(\.name),
      ["Research", "Seminar", "Reading"])

    let root = try XCTUnwrap(JSONSerialization.jsonObject(with: replaced) as? [String: Any])
    let storedDraft = try XCTUnwrap(root["draft"] as? [String: Any])
    XCTAssertEqual(
      Set(storedDraft.keys),
      Set(["folder", "title", "template", "tags", "pageSize", "orientation"]))
    let templates = try XCTUnwrap(root["startingTemplates"] as? [[String: Any]])
    XCTAssertEqual(
      Set(try XCTUnwrap(templates.first).keys),
      Set(["name", "folder", "paper", "pageSize", "orientation", "tags"]))
  }

  func testCompletingNewNoteCreationClearsDraftAndPreservesStartingTemplates() throws {
    let draft = NewNoteDraft(
      folder: [],
      title: "Draft",
      template: "blank",
      tags: ["Draft tag"],
      pageSize: "a4",
      orientation: "portrait")
    let template = NewNoteStartingTemplate(
      name: "Seminar",
      folder: [],
      paper: "dotted",
      pageSize: "a4",
      orientation: nil,
      tags: ["Template tag"])
    var data = try LibraryMetadataFile.settingNewNoteDraft(in: nil, draft: draft)
    data = try LibraryMetadataFile.settingNewNoteStartingTemplate(in: data, template: template)
    data = try LibraryMetadataFile.completingNewNoteCreation(
      in: data,
      path: ["Created"],
      tags: ["Created tag"])

    XCTAssertNil(try LibraryMetadataFile.newNoteDraft(in: data))
    XCTAssertEqual(try LibraryMetadataFile.newNoteStartingTemplates(in: data), [template])
    XCTAssertEqual(
      try LibraryMetadataFile.noteDetails(in: data, path: ["Created"]),
      LibraryNoteDetails(favorite: false, tags: ["Created tag"], description: ""))
    XCTAssertEqual(
      try LibraryMetadataFile.tags(in: data).map(\.name),
      ["Draft tag", "Template tag", "Created tag"])
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
        tags: ["Seminar", "Reading"]))
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

  func testLibraryTagCreationUsesChosenColorAndRejectsDuplicates() throws {
    let first = try LibraryMetadataFile.addingTag(
      in: nil,
      name: "Research",
      color: "#8B5CF6")
    XCTAssertEqual(
      try LibraryMetadataFile.tags(in: first),
      [LibraryTag(name: "Research", color: "#8B5CF6")])

    XCTAssertThrowsError(
      try LibraryMetadataFile.addingTag(
        in: first,
        name: "Research",
        color: "#2F6FEB"))
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
