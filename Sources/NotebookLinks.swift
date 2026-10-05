import Foundation

enum NotebookLinkTarget: Equatable {
  case external(URL)
  case page(reference: NotebookReference, file: String, id: String)
}

enum NotebookLinkError: LocalizedError {
  case empty
  case unsupportedScheme(String)
  case invalidDestination
  case outsideNotesRoot

  var errorDescription: String? {
    switch self {
    case .empty:
      "Choose a link destination."
    case .unsupportedScheme:
      "This link protocol is not supported."
    case .invalidDestination:
      "The link must name a notebook page."
    case .outsideNotesRoot:
      "Choose a page in the notes folder."
    }
  }
}

enum NotebookLink {
  static func href(
    source: NotebookReference,
    sourceFile: String,
    target: NotebookReference,
    mark: EngineNavigationMark
  ) throws -> String {
    let sourceDirectory = source.path + Array(split(sourceFile).dropLast())
    let targetFile = target.path + split(mark.file)
    guard targetFile.count >= 3,
      targetFile[targetFile.count - 2] == "pages",
      targetFile.last?.hasSuffix(".svg") == true
    else {
      throw NotebookLinkError.invalidDestination
    }

    let common = commonPrefixLength(sourceDirectory, targetFile)
    var parts = Array(repeating: "..", count: sourceDirectory.count - common)
    parts.append(contentsOf: targetFile.dropFirst(common))
    let path = parts.map(encodePathSegment).joined(separator: "/")
    guard !path.isEmpty else { throw NotebookLinkError.invalidDestination }
    guard !mark.id.isEmpty else { return path }
    let fragment = mark.id.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? mark.id
    return "\(path)#\(fragment)"
  }

  static func resolve(
    source: NotebookReference,
    sourceFile: String,
    href rawHref: String
  ) throws -> NotebookLinkTarget {
    let href = rawHref.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !href.isEmpty else { throw NotebookLinkError.empty }
    guard let components = URLComponents(string: href) else {
      throw NotebookLinkError.invalidDestination
    }

    if let scheme = components.scheme?.lowercased() {
      guard ["http", "https", "mailto"].contains(scheme) else {
        throw NotebookLinkError.unsupportedScheme(scheme)
      }
      guard let url = components.url else { throw NotebookLinkError.invalidDestination }
      return .external(url)
    }

    guard components.host == nil,
      components.query == nil,
      !components.path.hasPrefix("/")
    else {
      throw NotebookLinkError.outsideNotesRoot
    }

    var resolved = source.path + Array(split(sourceFile).dropLast())
    for part in split(components.path) {
      switch part {
      case ".":
        continue
      case "..":
        guard !resolved.isEmpty else { throw NotebookLinkError.outsideNotesRoot }
        resolved.removeLast()
      default:
        resolved.append(part)
      }
    }

    guard resolved.count >= 3,
      resolved[resolved.count - 2] == "pages",
      resolved.last?.hasSuffix(".svg") == true
    else {
      throw NotebookLinkError.invalidDestination
    }

    let reference = NotebookReference(path: Array(resolved.dropLast(2)))
    guard !reference.path.isEmpty else { throw NotebookLinkError.outsideNotesRoot }
    return .page(
      reference: reference,
      file: "pages/\(resolved.last!)",
      id: components.fragment ?? "")
  }

  private static func split(_ path: String) -> [String] {
    path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
  }

  private static func commonPrefixLength(_ left: [String], _ right: [String]) -> Int {
    var count = 0
    for (a, b) in zip(left, right) {
      guard a == b else { break }
      count += 1
    }
    return count
  }

  private static func encodePathSegment(_ segment: String) -> String {
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "/?#")
    return segment.addingPercentEncoding(withAllowedCharacters: allowed) ?? segment
  }
}
