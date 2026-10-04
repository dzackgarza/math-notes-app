struct PageMenuAvailability: Equatable {
  let drawing: Bool
  let pageCount: Int

  var pageOverview: Bool { !drawing }
  var goToPage: Bool { !drawing && pageCount > 0 }
  var pageMutation: Bool { !drawing }
  var selectPage: Bool { true }
  var clearPage: Bool { !drawing }
  var paper: Bool { !drawing }
  var bookmarks: Bool { true }
  var addBookmark: Bool { !drawing }
  var layers: Bool { !drawing }
  var deletePage: Bool { !drawing && pageCount > 1 }
}
