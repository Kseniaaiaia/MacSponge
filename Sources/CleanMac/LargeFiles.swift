import AppKit
import Observation

struct BigFile: Identifiable, Hashable, Sendable {
    let url: URL
    let size: Int64
    let lastUsed: Date
    var id: URL { url }
}

enum LargeFilesService {
    static func scan(minSize: Int64, progress: @escaping @Sendable (Int) -> Void) -> [BigFile] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isPackageKey, .totalFileAllocatedSizeKey,
                                         .fileAllocatedSizeKey, .contentModificationDateKey, .contentAccessDateKey]
        let skip: Set<String> = [FS.library.path, FS.home.appendingPathComponent(".Trash").path]
        guard let en = FS.fm.enumerator(at: FS.home, includingPropertiesForKeys: Array(keys),
                                        options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                        errorHandler: { _, _ in true }) else { return [] }
        var out: [BigFile] = []
        var seen = 0
        while let u = en.nextObject() as? URL {
            if skip.contains(u.path) { en.skipDescendants(); continue }
            guard let rv = try? u.resourceValues(forKeys: keys),
                  rv.isRegularFile == true, rv.isPackage != true else { continue }
            seen += 1
            if seen % 2000 == 0 { progress(seen) }
            let size = Int64(rv.totalFileAllocatedSize ?? rv.fileAllocatedSize ?? 0)
            guard size >= minSize else { continue }
            // "last used" = latest of modified/accessed, so recently-opened files aren't flagged as old
            let used = max(rv.contentModificationDate ?? .distantPast, rv.contentAccessDate ?? .distantPast)
            out.append(BigFile(url: u, size: size, lastUsed: used))
        }
        progress(seen)
        return Array(out.sorted { $0.size > $1.size }.prefix(1000))
    }

    static func trash(_ files: [BigFile]) -> (freed: Int64, failed: Int, done: Set<URL>) {
        var freed: Int64 = 0, failed = 0
        var done = Set<URL>()
        for f in files {
            guard FS.isSafeToDelete(f.url) else { failed += 1; continue }
            do { try FS.fm.trashItem(at: f.url, resultingItemURL: nil); freed += f.size; done.insert(f.url) }
            catch { failed += 1 }
        }
        return (freed, failed, done)
    }
}

@Observable @MainActor
final class LargeFilesModel {
    static let sizeOptions: [(label: String, mb: Int)] = [("50 MB", 50), ("100 MB", 100), ("500 MB", 500), ("1 GB", 1000)]
    static let ageOptions: [(label: String, days: Int)] = [("Any age", 0), ("3+ months", 90), ("6+ months", 180), ("1+ year", 365), ("2+ years", 730)]

    var minSizeMB = 100
    var minAgeDays = 180
    var all: [BigFile] = []
    var selection = Set<URL>()
    var isScanning = false
    var hasScanned = false
    var scanned = 0
    var message: String?

    var visible: [BigFile] {
        guard minAgeDays > 0 else { return all }
        let cutoff = Date().addingTimeInterval(-Double(minAgeDays) * 86_400)
        return all.filter { $0.lastUsed < cutoff }
    }
    var selectedFiles: [BigFile] { visible.filter { selection.contains($0.url) } }
    var selectedSize: Int64 { selectedFiles.reduce(0) { $0 + $1.size } }

    func scan() async {
        isScanning = true; message = nil; scanned = 0; selection = []
        let min = Int64(minSizeMB) * 1_000_000
        let report: @Sendable (Int) -> Void = { [weak self] n in Task { @MainActor in self?.scanned = n } }
        let found = await Task.detached { LargeFilesService.scan(minSize: min, progress: report) }.value
        all = found
        hasScanned = true
        isScanning = false
    }

    func trashSelected() async {
        let files = selectedFiles
        let r = await Task.detached { LargeFilesService.trash(files) }.value
        all.removeAll { r.done.contains($0.url) }
        selection.subtract(r.done)
        message = r.failed == 0
            ? "Moved \(r.done.count) file(s) to Trash — \(r.freed.bytesString) (empty the Trash to reclaim it)"
            : "Moved \(r.done.count) file(s); \(r.failed) failed"
    }
}
