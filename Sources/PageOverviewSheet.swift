import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers
import UIKit

@MainActor
struct PageOverviewSheet: View {
  let document: EngineDocument
  @Binding var currentPage: Int
  let onSelect: (Int) -> Void
  let onEdit: (Int) -> Void
  let onError: (Error) -> Void
  let onDone: () -> Void

  @State private var pageCount: Int
  @State private var thumbnailRevision = 0

  init(
    document: EngineDocument,
    currentPage: Binding<Int>,
    onSelect: @escaping (Int) -> Void,
    onEdit: @escaping (Int) -> Void,
    onError: @escaping (Error) -> Void,
    onDone: @escaping () -> Void
  ) {
    self.document = document
    _currentPage = currentPage
    self.onSelect = onSelect
    self.onEdit = onEdit
    self.onError = onError
    self.onDone = onDone
    _pageCount = State(initialValue: (try? document.pageCount()) ?? 0)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 16)],
          spacing: 16
        ) {
          ForEach(0..<pageCount, id: \.self) { index in
            pageCard(index)
          }
        }
        .padding(16)
        .frame(maxWidth: 900)
        .frame(maxWidth: .infinity)
      }
      .background(NativeTheme.leaf)
      .foregroundStyle(NativeTheme.ink)
      .font(NativeTheme.body)
      .tint(NativeTheme.ink)
      .navigationTitle("Pages")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(NativeTheme.leaf, for: .navigationBar)
      .toolbarBackground(.visible, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done", action: onDone)
        }
      }
    }
  }

  private func pageCard(_ index: Int) -> some View {
    VStack(spacing: 6) {
      Button {
        onSelect(index)
      } label: {
        PageOverviewThumbnail(
          document: document,
          index: index,
          revision: thumbnailRevision)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(NativeTheme.paper)
          .overlay {
            Rectangle()
              .stroke(
                pageCount > 1 && index == currentPage
                  ? NativeTheme.ribbon
                  : NativeTheme.paperEdge,
                lineWidth: pageCount > 1 && index == currentPage ? 3 : 1)
          }
      }
      .buttonStyle(.plain)
      .hoverEffect(.highlight)
      .accessibilityLabel("Page \(index + 1)")
      .accessibilityAddTraits(pageCount > 1 && index == currentPage ? .isSelected : [])
      .draggable(PageOverviewDrag(index: index))
      .dropDestination(for: PageOverviewDrag.self) { items, _ in
        guard let source = items.first?.index else { return false }
        return movePage(from: source, to: index)
      }

      HStack(spacing: 4) {
        Text("\(index + 1)")
          .font(NativeTheme.body)
          .foregroundStyle(NativeTheme.ink)

        Menu {
          Button("Duplicate", systemImage: "plus.square.on.square") {
            duplicatePage(index)
          }
          if pageCount > 1 {
            Button("Delete", systemImage: "trash", role: .destructive) {
              deletePage(index)
            }
          }
        } label: {
          Image(systemName: "ellipsis.circle")
            .frame(width: 32, height: 32)
        }
        .accessibilityLabel("Page \(index + 1) actions")
      }
    }
    .aspectRatio(0.62, contentMode: .fit)
    .contextMenu {
      Button("Duplicate", systemImage: "plus.square.on.square") {
        duplicatePage(index)
      }

      if pageCount > 1 {
        Button("Delete", systemImage: "trash", role: .destructive) {
          deletePage(index)
        }
      }
    }
  }

  private func movePage(from: Int, to: Int) -> Bool {
    guard from >= 0, from < pageCount, to >= 0, to < pageCount else {
      return false
    }
    guard from != to else { return true }

    do {
      try document.movePage(from: from, to: to)
      if currentPage == from {
        currentPage = to
      } else if from < currentPage && currentPage <= to {
        currentPage -= 1
      } else if to <= currentPage && currentPage < from {
        currentPage += 1
      }
      thumbnailRevision &+= 1
      onEdit(currentPage)
      return true
    } catch {
      onError(error)
      return false
    }
  }

  private func duplicatePage(_ index: Int) {
    do {
      try document.duplicatePage(at: index)
      if index < currentPage {
        currentPage += 1
      }
      pageCount = try document.pageCount()
      thumbnailRevision &+= 1
      onEdit(currentPage)
    } catch {
      onError(error)
    }
  }

  private func deletePage(_ index: Int) {
    guard pageCount > 1 else { return }
    let previousCount = pageCount
    do {
      try document.deletePage(at: index)
      if index < currentPage || currentPage == previousCount - 1 {
        currentPage = max(0, currentPage - 1)
      }
      pageCount = try document.pageCount()
      thumbnailRevision &+= 1
      onEdit(currentPage)
    } catch {
      onError(error)
    }
  }
}

@MainActor
private struct PageOverviewThumbnail: View {
  let document: EngineDocument
  let index: Int
  let revision: Int

  @State private var image: UIImage?
  @State private var failed = false

  var body: some View {
    ZStack {
      Rectangle()
        .fill(.background)

      if let image {
        Image(uiImage: image)
          .resizable()
          .scaledToFit()
      } else if failed {
        Image(systemName: "exclamationmark.triangle")
          .foregroundStyle(.secondary)
      } else {
        ProgressView()
      }
    }
    .task(id: revision) {
      image = nil
      failed = false
      do {
        image = UIImage(data: try document.pagePNG(index: index, width: 240))
        if image == nil {
          failed = true
        }
      } catch {
        image = nil
        failed = true
      }
    }
  }
}

private struct PageOverviewDrag: Codable, Transferable {
  let index: Int

  static var transferRepresentation: some TransferRepresentation {
    CodableRepresentation(contentType: .mathNotesPageOverviewDrag)
  }
}

private extension UTType {
  static let mathNotesPageOverviewDrag = UTType(
    exportedAs: "dev.zack.mathnotes.page-overview-drag")
}
