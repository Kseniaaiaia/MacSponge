import Foundation
import Observation

enum TrashService {
    static let url = FS.home.appendingPathComponent(".Trash")

    struct Scan: Sendable { var count = 0; var size: Int64 = 0; var accessible = true }

    static func scan() -> Scan {
        guard let items = try? FS.fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: []) else {
            return Scan(accessible: false)
        }
        let visible = items.filter { $0.lastPathComponent != ".DS_Store" }
        return Scan(count: visible.count, size: FS.sizes(of: items).reduce(0, +), accessible: true)
    }

    /// Permanently deletes everything in the Trash. Returns (freed bytes, failures).
    static func empty() -> (freed: Int64, failed: Int) {
        let items = FS.children(of: url)
        let sizes = FS.sizes(of: items)
        var freed: Int64 = 0, failed = 0
        for (item, size) in zip(items, sizes) {
            do { try FS.fm.removeItem(at: item); freed += size } catch { failed += 1 }
        }
        return (freed, failed)
    }
}

@Observable @MainActor
final class TrashModel {
    var count = 0
    var size: Int64 = 0
    var accessible = true
    var isBusy = false
    var message: String?

    func refresh() async {
        isBusy = true
        let r = await Task.detached { TrashService.scan() }.value
        count = r.count; size = r.size; accessible = r.accessible
        isBusy = false
    }

    func empty() async {
        isBusy = true
        let r = await Task.detached { TrashService.empty() }.value
        message = r.failed == 0
            ? "Freed \(r.freed.bytesString)"
            : "Freed \(r.freed.bytesString); \(r.failed) item(s) couldn't be removed"
        await refresh()
    }
}
