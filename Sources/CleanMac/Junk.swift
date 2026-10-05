import Foundation
import Observation

struct JunkItem: Identifiable, Hashable, Sendable {
    let url: URL
    let category: String
    let size: Int64
    var id: URL { url }
    var name: String { url.lastPathComponent }
}

struct JunkSource: Sendable {
    let name: String
    let icon: String
    let blurb: String
    let root: URL
    /// true: each child of `root` is its own item (per-app caches). false: `root` itself is the item.
    let perChild: Bool
}

enum JunkService {
    static let sources: [JunkSource] = {
        let lib = FS.library
        return [
            JunkSource(name: "User Caches", icon: "internaldrive", blurb: "App caches in ~/Library/Caches — apps rebuild them as needed.",
                       root: lib.appendingPathComponent("Caches"), perChild: true),
            JunkSource(name: "User Logs", icon: "doc.text", blurb: "Log and crash-report files in ~/Library/Logs.",
                       root: lib.appendingPathComponent("Logs"), perChild: true),
            JunkSource(name: "Xcode Derived Data", icon: "hammer", blurb: "Build products and indexes — regenerated on next build.",
                       root: lib.appendingPathComponent("Developer/Xcode/DerivedData"), perChild: true),
            JunkSource(name: "Xcode iOS Device Support", icon: "iphone", blurb: "Debug symbols per iOS version — re-downloaded when you plug a device in.",
                       root: lib.appendingPathComponent("Developer/Xcode/iOS DeviceSupport"), perChild: true),
            JunkSource(name: "Simulator Caches", icon: "ipad.and.iphone", blurb: "CoreSimulator cache files.",
                       root: lib.appendingPathComponent("Developer/CoreSimulator/Caches"), perChild: true),
            JunkSource(name: "npm Cache", icon: "shippingbox", blurb: "~/.npm/_cacache — re-downloaded on demand.",
                       root: FS.home.appendingPathComponent(".npm/_cacache"), perChild: false),
        ]
    }()

    static func scan() -> [JunkItem] {
        var out: [JunkItem] = []
        for s in sources {
            let urls = s.perChild ? FS.children(of: s.root).filter { $0.lastPathComponent != ".DS_Store" }
                                  : (FS.fm.fileExists(atPath: s.root.path) ? [s.root] : [])
            for (u, size) in zip(urls, FS.sizes(of: urls)) where size > 0 {
                out.append(JunkItem(url: u, category: s.name, size: size))
            }
        }
        return out
    }

    static func clean(_ items: [JunkItem]) -> (freed: Int64, failed: Int) {
        var freed: Int64 = 0, failed = 0
        for item in items {
            guard FS.isSafeToDelete(item.url) else { failed += 1; continue }
            do { try FS.fm.removeItem(at: item.url); freed += item.size } catch { failed += 1 }
        }
        return (freed, failed)
    }
}

@Observable @MainActor
final class JunkModel {
    var items: [JunkItem] = []
    var selection = Set<URL>()
    var isScanning = false
    var isCleaning = false
    var hasScanned = false
    var message: String?

    var selectedSize: Int64 { items.filter { selection.contains($0.url) }.reduce(0) { $0 + $1.size } }
    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }

    func items(in source: JunkSource) -> [JunkItem] {
        items.filter { $0.category == source.name }.sorted { $0.size > $1.size }
    }

    func scan() async {
        isScanning = true; message = nil
        let found = await Task.detached { JunkService.scan() }.value
        items = found
        selection = Set(found.map(\.url))
        hasScanned = true
        isScanning = false
    }

    func clean() async {
        isCleaning = true
        let chosen = items.filter { selection.contains($0.url) }
        let r = await Task.detached { JunkService.clean(chosen) }.value
        message = r.failed == 0
            ? "Freed \(r.freed.bytesString)"
            : "Freed \(r.freed.bytesString); \(r.failed) item(s) couldn't be removed"
        isCleaning = false
        await scan()
    }

    func toggleAll(in source: JunkSource, on: Bool) {
        for i in items(in: source) {
            if on { selection.insert(i.url) } else { selection.remove(i.url) }
        }
    }
}
