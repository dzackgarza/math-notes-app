import FileProvider
import UniformTypeIdentifiers

// One dataless file whose contents arrive 20 s after the system asks for them,
// standing in for an undownloaded Dropbox file.
let fileID = NSFileProviderItemIdentifier("notes.json")
let fileContents = Data("{\"fetched\":true}\n".utf8)
let fetchDelay: TimeInterval = 20

final class Item: NSObject, NSFileProviderItem {
  let itemIdentifier: NSFileProviderItemIdentifier
  let parentItemIdentifier: NSFileProviderItemIdentifier = .rootContainer
  let filename: String
  let contentType: UTType
  let documentSize: NSNumber?
  let capabilities: NSFileProviderItemCapabilities = [.allowsReading, .allowsContentEnumerating]
  let itemVersion = NSFileProviderItemVersion(contentVersion: Data([1]), metadataVersion: Data([1]))

  init(_ identifier: NSFileProviderItemIdentifier) {
    itemIdentifier = identifier
    if identifier == .rootContainer {
      filename = "FPSpike"
      contentType = .folder
      documentSize = nil
    } else {
      filename = identifier.rawValue
      contentType = .json
      documentSize = NSNumber(value: fileContents.count)
    }
  }
}

final class Extension: NSObject, NSFileProviderReplicatedExtension {
  required init(domain: NSFileProviderDomain) { super.init() }
  func invalidate() {}

  func item(
    for identifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest,
    completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void
  ) -> Progress {
    guard identifier == .rootContainer || identifier == fileID else {
      completionHandler(nil, NSFileProviderError(.noSuchItem))
      return Progress()
    }
    completionHandler(Item(identifier), nil)
    return Progress()
  }

  func fetchContents(
    for itemIdentifier: NSFileProviderItemIdentifier, version requestedVersion: NSFileProviderItemVersion?,
    request: NSFileProviderRequest, completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void
  ) -> Progress {
    NSLog("FPSpike fetchContents %@", itemIdentifier.rawValue)
    DispatchQueue.global().asyncAfter(deadline: .now() + fetchDelay) {
      let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      do {
        try fileContents.write(to: url)
        completionHandler(url, Item(itemIdentifier), nil)
      } catch {
        completionHandler(nil, nil, error)
      }
    }
    return Progress()
  }

  func createItem(
    basedOn itemTemplate: NSFileProviderItem, fields: NSFileProviderItemFields, contents url: URL?,
    options: NSFileProviderCreateItemOptions = [], request: NSFileProviderRequest,
    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void
  ) -> Progress {
    completionHandler(nil, [], false, NSError(domain: NSCocoaErrorDomain, code: NSFeatureUnsupportedError))
    return Progress()
  }

  func modifyItem(
    _ item: NSFileProviderItem, baseVersion version: NSFileProviderItemVersion,
    changedFields: NSFileProviderItemFields, contents newContents: URL?,
    options: NSFileProviderModifyItemOptions = [], request: NSFileProviderRequest,
    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void
  ) -> Progress {
    completionHandler(nil, [], false, NSError(domain: NSCocoaErrorDomain, code: NSFeatureUnsupportedError))
    return Progress()
  }

  func deleteItem(
    identifier: NSFileProviderItemIdentifier, baseVersion version: NSFileProviderItemVersion,
    options: NSFileProviderDeleteItemOptions = [], request: NSFileProviderRequest,
    completionHandler: @escaping (Error?) -> Void
  ) -> Progress {
    completionHandler(NSError(domain: NSCocoaErrorDomain, code: NSFeatureUnsupportedError))
    return Progress()
  }

  func enumerator(
    for containerItemIdentifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest
  ) throws -> NSFileProviderEnumerator {
    Enumerator(container: containerItemIdentifier)
  }
}

final class Enumerator: NSObject, NSFileProviderEnumerator {
  let container: NSFileProviderItemIdentifier
  init(container: NSFileProviderItemIdentifier) { self.container = container }
  func invalidate() {}

  func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
    observer.didEnumerate(container == .rootContainer ? [Item(fileID)] : [])
    observer.finishEnumerating(upTo: nil)
  }

  func enumerateChanges(for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor) {
    observer.finishEnumeratingChanges(upTo: anchor, moreComing: false)
  }

  func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
    completionHandler(NSFileProviderSyncAnchor(Data([0])))
  }
}
