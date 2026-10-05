import SwiftUI
import AppKit

extension Int64 {
    var bytesString: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }
}

extension Binding where Value == Set<URL> {
    /// A Bool binding for "is this URL in the set" — handy for checkbox rows.
    func contains(_ url: URL) -> Binding<Bool> {
        Binding<Bool>(
            get: { wrappedValue.contains(url) },
            set: { on in
                if on { wrappedValue.insert(url) } else { wrappedValue.remove(url) }
            }
        )
    }
}

enum FS {
    static let fm = FileManager.default
    static let home = fm.homeDirectoryForCurrentUser
    static let library = home.appendingPathComponent("Library")

    private static let sizeKeys: Set<URLResourceKey> = [
        .isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey
    ]

    /// On-disk size of a file or a whole directory tree. Blocking — call off the main thread.
    static func allocatedSize(of url: URL) -> Int64 {
        guard let v = try? url.resourceValues(forKeys: sizeKeys), v.isSymbolicLink != true else { return 0 }
        if v.isDirectory != true {
            return Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        var total: Int64 = 0
        guard let en = fm.enumerator(at: url, includingPropertiesForKeys: Array(sizeKeys),
                                     options: [], errorHandler: { _, _ in true }) else { return 0 }
        while let u = en.nextObject() as? URL {
            if Task.isCancelled { break }
            // firmlinked / mounted volumes would double-count the whole disk
            if u.path == "/System/Volumes" || u.path == "/Volumes" { en.skipDescendants(); continue }
            guard let rv = try? u.resourceValues(forKeys: sizeKeys),
                  rv.isSymbolicLink != true, rv.isDirectory != true else { continue }
            total += Int64(rv.totalFileAllocatedSize ?? rv.fileAllocatedSize ?? 0)
        }
        return total
    }

    /// Sizes of many items computed in parallel, returned in the same order.
    static func sizes(of urls: [URL]) -> [Int64] {
        var result = [Int64](repeating: 0, count: urls.count)
        result.withUnsafeMutableBufferPointer { buf in
            let base = buf.baseAddress!
            DispatchQueue.concurrentPerform(iterations: urls.count) { i in
                base[i] = allocatedSize(of: urls[i])
            }
        }
        return result
    }

    static func children(of url: URL) -> [URL] {
        (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])) ?? []
    }

    static func diskSpace() -> (free: Int64, total: Int64) {
        let v = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        return (v?.volumeAvailableCapacityForImportantUsage ?? 0, Int64(v?.volumeTotalCapacity ?? 0))
    }

    /// Full Disk Access probe: ~/Library/Safari is TCC-protected.
    static func hasFullDiskAccess() -> Bool {
        (try? fm.contentsOfDirectory(atPath: library.appendingPathComponent("Safari").path)) != nil
    }

    static func isSafeToDelete(_ url: URL) -> Bool {
        let p = url.standardizedFileURL.path
        return p.hasPrefix(home.path + "/") && p != home.path && p != library.path
    }
}
