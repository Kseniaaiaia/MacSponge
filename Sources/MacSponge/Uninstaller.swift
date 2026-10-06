import AppKit
import Observation

struct AppInfo: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    let bundleID: String
    let version: String
    var size: Int64 = 0
    var id: URL { url }
}

struct Leftover: Identifiable, Hashable, Sendable {
    let url: URL
    let kind: String
    let size: Int64
    var id: URL { url }
}

enum UninstallService {
    static func listApps() -> [AppInfo] {
        let roots = [URL(fileURLWithPath: "/Applications"), FS.home.appendingPathComponent("Applications")]
        var found: [AppInfo] = []
        func consider(_ u: URL) {
            guard let b = Bundle(url: u), let id = b.bundleIdentifier,
                  !id.hasPrefix("com.apple."), id != Bundle.main.bundleIdentifier else { return }
            let name = (b.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (b.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? u.deletingPathExtension().lastPathComponent
            let ver = (b.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
            found.append(AppInfo(url: u, name: name, bundleID: id, version: ver))
        }
        for root in roots {
            for u in FS.children(of: root) {
                if u.pathExtension == "app" { consider(u) }
                else if (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    // vendor folders such as /Applications/Utilities or /Applications/Adobe …
                    for inner in FS.children(of: u) where inner.pathExtension == "app" { consider(inner) }
                }
            }
        }
        return found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static let locations: [(path: String, kind: String, matchName: Bool, loose: Bool)] = [
        ("Application Support", "Application Support", true, false),
        ("Caches", "Caches", true, false),
        ("Logs", "Logs", true, false),
        ("Preferences", "Preferences", false, false),
        ("Preferences/ByHost", "Preferences", false, false),
        ("Containers", "Container", false, false),
        ("Group Containers", "Group Container", false, true),
        ("Saved Application State", "Saved State", false, false),
        ("HTTPStorages", "HTTP Storage", false, false),
        ("WebKit", "WebKit Data", false, false),
        ("Cookies", "Cookies", false, false),
        ("LaunchAgents", "Launch Agent", false, false),
        ("Application Scripts", "Scripts", false, false),
    ]

    static func findLeftovers(for app: AppInfo) -> [Leftover] {
        let b = app.bundleID.lowercased()
        let n = app.url.deletingPathExtension().lastPathComponent.lowercased()
        let displayName = app.name.lowercased()
        var urls: [(URL, String)] = []
        for loc in locations {
            let dir = FS.library.appendingPathComponent(loc.path)
            for child in FS.children(of: dir) {
                let f = child.lastPathComponent.lowercased()
                var hit = f == b || f.hasPrefix(b + ".")
                if loc.loose && f.contains(b) { hit = true }
                if loc.matchName && n.count >= 3 && (f == n || f == displayName) { hit = true }
                if hit { urls.append((child, loc.kind)) }
            }
        }
        let sizes = FS.sizes(of: urls.map(\.0))
        return zip(urls, sizes).map { Leftover(url: $0.0.0, kind: $0.0.1, size: $0.1) }
            .sorted { $0.size > $1.size }
    }

    static func uninstall(app: AppInfo, leftovers: [Leftover]) -> (trashed: Int, errors: [String]) {
        var ok = 0, errors: [String] = []
        for u in [app.url] + leftovers.map(\.url) {
            guard u == app.url || FS.isSafeToDelete(u) else { continue }
            do { try FS.fm.trashItem(at: u, resultingItemURL: nil); ok += 1 }
            catch { errors.append("\(u.lastPathComponent): \(error.localizedDescription)") }
        }
        return (ok, errors)
    }
}

@Observable @MainActor
final class UninstallModel {
    var apps: [AppInfo] = []
    var selectedID: URL?
    var leftovers: [Leftover] = []
    var leftoverSelection = Set<URL>()
    var isLoading = false
    var isFindingLeftovers = false
    var isWorking = false
    var message: String?
    var search = ""

    var selected: AppInfo? { apps.first { $0.id == selectedID } }
    var filtered: [AppInfo] {
        search.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }
    var removalSize: Int64 {
        (selected?.size ?? 0) + leftovers.filter { leftoverSelection.contains($0.url) }.reduce(0) { $0 + $1.size }
    }

    func load() async {
        isLoading = true
        apps = await Task.detached { UninstallService.listApps() }.value
        isLoading = false
        let urls = apps.map(\.url)
        // sizes trickle in so the list shows up immediately
        Task.detached {
            for u in urls {
                let s = FS.allocatedSize(of: u)
                await MainActor.run { [weak self] in
                    if let i = self?.apps.firstIndex(where: { $0.url == u }) { self?.apps[i].size = s }
                }
            }
        }
    }

    func select(_ id: URL?) async {
        selectedID = id
        leftovers = []; leftoverSelection = []; message = nil
        guard let app = selected else { return }
        isFindingLeftovers = true
        let found = await Task.detached { UninstallService.findLeftovers(for: app) }.value
        guard selectedID == id else { return }
        leftovers = found
        leftoverSelection = Set(found.map(\.url))
        isFindingLeftovers = false
    }

    func uninstall() async {
        guard let app = selected else { return }
        if NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == app.bundleID }) {
            message = "\(app.name) is running — quit it first."
            return
        }
        let chosen = leftovers.filter { leftoverSelection.contains($0.url) }
        isWorking = true; message = nil
        let r = await Task.detached { UninstallService.uninstall(app: app, leftovers: chosen) }.value
        message = r.errors.isEmpty
            ? "Moved \(r.trashed) item(s) to Trash"
            : "Moved \(r.trashed) item(s); failed: " + r.errors.joined(separator: "; ")
        selectedID = nil; leftovers = []; leftoverSelection = []
        isWorking = false
        apps = await Task.detached { UninstallService.listApps() }.value
    }
}
