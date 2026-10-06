import SwiftUI
import Observation

struct SpaceEntry: Identifiable, Hashable, Sendable {
    let url: URL
    var size: Int64?          // nil while still being measured
    let isDir: Bool
    var id: URL { url }
    var name: String { url.lastPathComponent }
    var selectable: Bool { FS.isSafeToDelete(url) }
}

enum SpaceRoot: String, CaseIterable, Identifiable {
    case home = "Home", disk = "Macintosh HD"
    var id: String { rawValue }
    var url: URL { self == .home ? FS.home : URL(fileURLWithPath: "/") }
}

enum SpaceService {
    private static let skipAtRoot: Set<String> = ["/Volumes", "/dev", "/System/Volumes", "/home", "/net"]

    static func list(_ dir: URL) -> [SpaceEntry] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]
        return FS.children(of: dir).compactMap { u in
            if skipAtRoot.contains(u.path) { return nil }
            guard let v = try? u.resourceValues(forKeys: keys), v.isSymbolicLink != true else { return nil }
            return SpaceEntry(url: u, size: nil, isDir: v.isDirectory == true && v.isPackage != true)
        }
    }
}

@Observable @MainActor
final class SpaceLensModel {
    var root: SpaceRoot = .home
    var path: [URL] = []
    var entries: [SpaceEntry] = []
    var selection = Set<URL>()
    var pending = 0
    var isTrashing = false
    var message: String?

    private var generation = 0
    private var cache: [URL: [SpaceEntry]] = [:]

    var current: URL { path.last ?? root.url }
    var sorted: [SpaceEntry] {
        entries.sorted { ($0.size ?? -1) > ($1.size ?? -1) }
    }
    var selectedSize: Int64 { entries.filter { selection.contains($0.url) }.reduce(0) { $0 + ($1.size ?? 0) } }

    func start(_ newRoot: SpaceRoot? = nil) async {
        if let newRoot { root = newRoot }
        path = [root.url]
        await load()
    }

    func open(_ url: URL) async { path.append(url); await load() }
    func back() async { if path.count > 1 { path.removeLast(); await load() } }
    func jump(to index: Int) async { path = Array(path.prefix(index + 1)); await load() }

    func load() async {
        generation += 1
        let gen = generation
        selection = []; message = nil
        let dir = current
        if let c = cache[dir] { entries = c; pending = 0; return }
        let kids = await Task.detached { SpaceService.list(dir) }.value
        guard gen == generation else { return }
        entries = kids
        pending = kids.count
        await withTaskGroup(of: (URL, Int64).self) { group in
            for k in kids { group.addTask { (k.url, FS.allocatedSize(of: k.url)) } }
            for await (u, s) in group {
                guard gen == generation else { group.cancelAll(); continue }
                if let i = entries.firstIndex(where: { $0.url == u }) { entries[i].size = s }
                pending -= 1
            }
        }
        if gen == generation { cache[dir] = entries }
    }

    func trashSelected() async {
        let chosen = entries.filter { selection.contains($0.url) && $0.selectable }
        isTrashing = true; message = nil
        let r = await Task.detached { () -> (Int64, Set<URL>, Int) in
            var freed: Int64 = 0, done = Set<URL>(), failed = 0
            for e in chosen {
                do { try FS.fm.trashItem(at: e.url, resultingItemURL: nil); freed += e.size ?? 0; done.insert(e.url) }
                catch { failed += 1 }
            }
            return (freed, done, failed)
        }.value
        entries.removeAll { r.1.contains($0.url) }
        selection.subtract(r.1)
        cache = [:]   // parent sizes are stale now
        isTrashing = false
        message = r.2 == 0 ? "Moved \(r.1.count) item(s) to Trash — \(r.0.bytesString)"
                           : "Moved \(r.1.count) item(s); \(r.2) failed"
    }
}

// MARK: - Views

struct SpaceLensView: View {
    @Bindable var model: SpaceLensModel
    @State private var confirm = false

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Space Lens", subtitle: "See what takes up space. Click a folder to look inside.")
            HStack {
                Button { Task { await model.back() } } label: { Image(systemName: "chevron.left") }
                    .disabled(model.path.count <= 1)
                Text((model.current.path as NSString).abbreviatingWithTildeInPath)
                    .font(.callout).lineLimit(1).truncationMode(.head)
                if model.pending > 0 { ProgressView().controlSize(.small); Text("measuring \(model.pending)…").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Picker("", selection: Binding(get: { model.root }, set: { r in Task { await model.start(r) } })) {
                    ForEach(SpaceRoot.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).fixedSize()
            }
            .padding(.horizontal, 24).padding(.bottom, 10)
            Divider()
            HStack(spacing: 0) {
                list.frame(width: 440)
                Divider()
                BubbleChart(entries: model.entries) { e in if e.isDir { Task { await model.open(e.url) } } }
                    .padding(16)
            }
            BottomBar(text: model.isTrashing ? "Moving to the Trash…"
                      : model.message ?? (model.selection.isEmpty ? "Tick items to remove them" : "\(model.selection.count) selected · \(model.selectedSize.bytesString)")) {
                BusyButton(title: "Move to Trash", busyTitle: "Moving…", isBusy: model.isTrashing,
                           disabled: model.selection.isEmpty) { confirm = true }
            }
        }
        .task { if model.path.isEmpty { await model.start() } }
        .alert("Move \(model.selection.count) item(s) to the Trash?", isPresented: $confirm) {
            Button("Move to Trash", role: .destructive) { Task { await model.trashSelected() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(model.selectedSize.bytesString) — you can still restore them from the Trash.")
        }
    }

    private var list: some View {
        let maxSize = Double(model.entries.compactMap(\.size).max() ?? 1)
        return List(model.sorted) { e in
            HStack(spacing: 10) {
                Toggle("", isOn: $model.selection.contains(e.url))
                    .labelsHidden().toggleStyle(.checkbox).disabled(!e.selectable || e.size == nil)
                FileIcon(url: e.url)
                VStack(alignment: .leading, spacing: 3) {
                    Text(e.name).lineLimit(1).truncationMode(.middle)
                    GeometryReader { g in
                        Capsule().fill(.tint.opacity(0.6))
                            .frame(width: max(2, g.size.width * Double(e.size ?? 0) / maxSize))
                    }.frame(height: 4)
                }
                Text(e.size.map(\.bytesString) ?? "…").monospacedDigit().foregroundStyle(.secondary)
                    .frame(width: 76, alignment: .trailing)
                Image(systemName: "chevron.right").foregroundStyle(.tertiary).opacity(e.isDir ? 1 : 0)
            }
            .contentShape(Rectangle())
            .onTapGesture { if e.isDir { Task { await model.open(e.url) } } }
            .contextMenu { Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([e.url]) } }
        }
    }
}

struct BubbleChart: View {
    let entries: [SpaceEntry]
    let open: (SpaceEntry) -> Void

    var body: some View {
        GeometryReader { geo in
            let items = Array(entries.filter { ($0.size ?? 0) > 0 }
                .sorted { $0.size! > $1.size! }.prefix(14))
            if items.isEmpty {
                Text("Nothing to show").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let maxS = Double(items[0].size!)
                let radii = items.map { max(sqrt(Double($0.size!) / maxS), 0.16) }
                let centers = Self.pack(radii)
                let minX = zip(centers, radii).map { $0.0.x - $0.1 }.min()!
                let maxX = zip(centers, radii).map { $0.0.x + $0.1 }.max()!
                let minY = zip(centers, radii).map { $0.0.y - $0.1 }.min()!
                let maxY = zip(centers, radii).map { $0.0.y + $0.1 }.max()!
                let scale = min(geo.size.width / (maxX - minX), geo.size.height / (maxY - minY)) * 0.96
                ZStack {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, e in
                        let d = radii[i] * scale * 2
                        Circle()
                            .fill(Color(hue: 0.48 + Double(i) * 0.045, saturation: 0.55, brightness: 0.8).gradient)
                            .overlay {
                                if d > 70 {
                                    VStack(spacing: 2) {
                                        Image(nsImage: NSWorkspace.shared.icon(forFile: e.url.path))
                                            .resizable().frame(width: min(d * 0.28, 44), height: min(d * 0.28, 44))
                                        Text(e.name).font(.caption.bold()).lineLimit(1)
                                        Text(e.size!.bytesString).font(.caption2)
                                    }
                                    .foregroundStyle(.white).padding(6)
                                }
                            }
                            .frame(width: d, height: d)
                            .help("\(e.name) — \(e.size!.bytesString)")
                            .position(x: geo.size.width / 2 + (centers[i].x - (minX + maxX) / 2) * scale,
                                      y: geo.size.height / 2 + (centers[i].y - (minY + maxY) / 2) * scale)
                            .onTapGesture { open(e) }
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: items.map(\.id))
            }
        }
    }

    /// Greedy circle packing: biggest in the middle, each next one as close to it as it fits.
    static func pack(_ r: [Double]) -> [CGPoint] {
        var pts: [CGPoint] = []
        for (i, ri) in r.enumerated() {
            if i == 0 { pts.append(.zero); continue }
            var dist = r[0] + ri
            while true {
                var best: CGPoint?
                var bestD = Double.infinity
                for deg in stride(from: 0.0, to: 360.0, by: 5.0) {
                    let a = deg * .pi / 180
                    let p = CGPoint(x: dist * cos(a), y: dist * sin(a))
                    let fits = pts.indices.allSatisfy { hypot(p.x - pts[$0].x, p.y - pts[$0].y) >= ri + r[$0] + 0.02 }
                    if fits, hypot(p.x, p.y) < bestD { best = p; bestD = hypot(p.x, p.y) }
                }
                if let b = best { pts.append(b); break }
                dist += 0.04
            }
        }
        return pts
    }
}
