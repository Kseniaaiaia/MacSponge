import SwiftUI

enum Tool: String, CaseIterable, Identifiable {
    case trash, junk, uninstaller, space, large
    var id: String { rawValue }
    var title: String {
        switch self {
        case .trash: "Trash"
        case .junk: "System Junk"
        case .uninstaller: "Uninstaller"
        case .space: "Space Lens"
        case .large: "Large & Old Files"
        }
    }
    var icon: String {
        switch self {
        case .trash: "trash"
        case .junk: "sparkles"
        case .uninstaller: "xmark.app"
        case .space: "chart.pie"
        case .large: "doc.zipper"
        }
    }
}

struct RootView: View {
    @State private var tool: Tool? = .trash
    @State private var trash = TrashModel()
    @State private var junk = JunkModel()
    @State private var uninstaller = UninstallModel()
    @State private var space = SpaceLensModel()
    @State private var large = LargeFilesModel()
    @State private var hasFDA = FS.hasFullDiskAccess()

    var body: some View {
        NavigationSplitView {
            List(Tool.allCases, selection: $tool) { t in
                Label(t.title, systemImage: t.icon).tag(t)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
            .safeAreaInset(edge: .bottom) { DiskUsageView().padding(12) }
        } detail: {
            VStack(spacing: 0) {
                if !hasFDA { FullDiskAccessBanner { hasFDA = FS.hasFullDiskAccess() } }
                switch tool ?? .trash {
                case .trash: TrashView(model: trash)
                case .junk: JunkView(model: junk)
                case .uninstaller: UninstallerView(model: uninstaller)
                case .space: SpaceLensView(model: space)
                case .large: LargeFilesView(model: large)
                }
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasFDA = FS.hasFullDiskAccess()
        }
    }
}

struct DiskUsageView: View {
    var body: some View {
        let d = FS.diskSpace()
        let used = Double(max(d.total - d.free, 0))
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: d.total > 0 ? used / Double(d.total) : 0)
            Text("\(d.free.bytesString) free of \(d.total.bytesString)")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct FullDiskAccessBanner: View {
    let recheck: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield").font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Full Disk Access needed").bold()
                Text("Without it macOS hides the Trash and some caches from CleanMac. Add CleanMac in Privacy & Security → Full Disk Access, then reopen the app.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
            }
        }
        .padding(12)
        .background(.orange.opacity(0.15))
    }
}

// MARK: - Shared bits

struct PageHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title.bold())
            Text(subtitle).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 12)
    }
}

struct BottomBar<Trailing: View>: View {
    let text: String
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack {
            Text(text).foregroundStyle(.secondary).lineLimit(2)
            Spacer()
            trailing
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
        .background(.bar)
    }
}

struct FileIcon: View {
    let url: URL
    var size: CGFloat = 28
    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
            .resizable().frame(width: size, height: size)
    }
}

/// Prominent button that swaps its label for a spinner + busy title while work is running.
struct BusyButton: View {
    let title: String
    let busyTitle: String
    let isBusy: Bool
    var disabled = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isBusy { ProgressView().controlSize(.small) }
                Text(isBusy ? busyTitle : title)
            }
            .frame(minWidth: 90)
        }
        .buttonStyle(.borderedProminent)
        .disabled(disabled || isBusy)
    }
}
