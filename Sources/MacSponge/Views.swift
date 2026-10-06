import SwiftUI

// MARK: - Trash

struct TrashView: View {
    let model: TrashModel
    @State private var confirm = false

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            MascotView(isScanning: model.isBusy, size: 240)
            Text(model.size.bytesString)
                .font(.system(size: 44, weight: .semibold, design: .rounded))
            Text(model.accessible
                 ? (model.count == 0 ? "The Trash is empty" : "\(model.count) item(s) in the Trash")
                 : "Can't read the Trash — grant Full Disk Access")
                .foregroundStyle(.secondary)
            BusyButton(title: "Empty Trash", busyTitle: "Emptying…", isBusy: model.isBusy, disabled: model.count == 0) { confirm = true }
                .controlSize(.large)
            if let m = model.message { Text(m).font(.callout).foregroundStyle(.green) }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .task { await model.refresh() }
        .alert("Empty the Trash?", isPresented: $confirm) {
            Button("Empty Trash", role: .destructive) { Task { await model.empty() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(model.size.bytesString) will be permanently deleted. This can't be undone.")
        }
    }
}

// MARK: - System Junk

struct JunkView: View {
    @Bindable var model: JunkModel
    @State private var confirm = false

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "System Junk", subtitle: "Caches, logs and developer leftovers that are safe to regenerate.")
            if model.isScanning || model.isCleaning {
                BusyMascot(title: model.isCleaning ? "Cleaning…" : "Scanning…")
            } else if !model.hasScanned {
                Spacer()
                Button("Scan") { Task { await model.scan() } }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                Spacer()
            } else if model.items.isEmpty {
                Spacer(); Text("Nothing to clean 🎉").foregroundStyle(.secondary); Spacer()
            } else {
                List {
                    ForEach(JunkService.sources, id: \.name) { source in
                        let rows = model.items(in: source)
                        if !rows.isEmpty {
                            Section {
                                ForEach(rows) { item in
                                    Toggle(isOn: $model.selection.contains(item.url)) {
                                        HStack {
                                            Text(item.name).lineLimit(1).truncationMode(.middle)
                                            Spacer()
                                            Text(item.size.bytesString).foregroundStyle(.secondary).monospacedDigit()
                                        }
                                    }
                                    .toggleStyle(.checkbox)
                                }
                            } header: {
                                HStack {
                                    Label(source.name, systemImage: source.icon).font(.headline)
                                    Text(rows.reduce(0) { $0 + $1.size }.bytesString).foregroundStyle(.secondary)
                                    Spacer()
                                    Button("All") { model.toggleAll(in: source, on: true) }.buttonStyle(.link)
                                    Button("None") { model.toggleAll(in: source, on: false) }.buttonStyle(.link)
                                }
                            } footer: {
                                Text(source.blurb).font(.caption)
                            }
                        }
                    }
                }
            }
            BottomBar(text: model.isCleaning ? "Cleaning \(model.selectedSize.bytesString)… don't close the app"
                      : model.message ?? (model.hasScanned ? "\(model.selectedSize.bytesString) selected of \(model.totalSize.bytesString)" : "")) {
                Button("Rescan") { Task { await model.scan() } }.disabled(model.isScanning || model.isCleaning)
                BusyButton(title: "Clean", busyTitle: "Cleaning…", isBusy: model.isCleaning,
                           disabled: model.selection.isEmpty || model.isScanning) { confirm = true }
            }
        }
        .task { if !model.hasScanned { await model.scan() } }
        .alert("Delete \(model.selectedSize.bytesString) of junk?", isPresented: $confirm) {
            Button("Delete", role: .destructive) { Task { await model.clean() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Selected items are permanently deleted. Apps will rebuild their caches as needed.")
        }
    }
}

// MARK: - Uninstaller

struct UninstallerView: View {
    @Bindable var model: UninstallModel
    @State private var confirm = false

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Uninstaller", subtitle: "Remove an app together with its preferences, caches and support files.")
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    TextField("Search apps", text: $model.search)
                        .textFieldStyle(.roundedBorder).padding(8)
                    List(model.filtered, selection: Binding(get: { model.selectedID }, set: { id in Task { await model.select(id) } })) { app in
                        HStack {
                            FileIcon(url: app.url)
                            VStack(alignment: .leading) {
                                Text(app.name).lineLimit(1)
                                if !app.version.isEmpty { Text(app.version).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Text(app.size > 0 ? app.size.bytesString : "…").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                        .tag(app.id)
                    }
                    .overlay { if model.isLoading { BusyMascot(title: "Loading apps…", size: 110) } }
                }
                .frame(width: 320)
                Divider()
                detail.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            BottomBar(text: model.isWorking ? "Uninstalling…"
                      : model.message ?? (model.selected != nil ? "\(model.removalSize.bytesString) will be moved to the Trash" : "")) {
                BusyButton(title: "Uninstall", busyTitle: "Uninstalling…", isBusy: model.isWorking,
                           disabled: model.selected == nil || model.isFindingLeftovers) { confirm = true }
            }
        }
        .task { if model.apps.isEmpty { await model.load() } }
        .alert("Uninstall \(model.selected?.name ?? "")?", isPresented: $confirm) {
            Button("Move to Trash", role: .destructive) { Task { await model.uninstall() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The app and \(model.leftoverSelection.count) selected leftover item(s) go to the Trash.")
        }
    }

    @ViewBuilder private var detail: some View {
        if let app = model.selected {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    FileIcon(url: app.url, size: 48)
                    VStack(alignment: .leading) {
                        Text(app.name).font(.title2.bold())
                        Text(app.bundleID).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(app.size.bytesString).font(.title3).monospacedDigit()
                }
                .padding(16)
                Divider()
                if model.isWorking {
                    BusyMascot(title: "Uninstalling…")
                } else if model.isFindingLeftovers {
                    BusyMascot(title: "Looking for leftovers…")
                } else if model.leftovers.isEmpty {
                    Spacer(); Text("No leftover files found").foregroundStyle(.secondary).frame(maxWidth: .infinity); Spacer()
                } else {
                    List(model.leftovers) { l in
                        Toggle(isOn: $model.leftoverSelection.contains(l.url)) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(l.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                                    Text(l.kind).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(l.size.bytesString).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
        } else {
            Text("Select an app").foregroundStyle(.secondary)
        }
    }
}

// MARK: - Large & Old files

struct LargeFilesView: View {
    @Bindable var model: LargeFilesModel
    @State private var confirm = false

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Large & Old Files", subtitle: "Big files in your home folder you haven't touched for a while.")
            HStack {
                Picker("Bigger than", selection: $model.minSizeMB) {
                    ForEach(LargeFilesModel.sizeOptions, id: \.mb) { Text($0.label).tag($0.mb) }
                }.fixedSize()
                Picker("Not used for", selection: $model.minAgeDays) {
                    ForEach(LargeFilesModel.ageOptions, id: \.days) { Text($0.label).tag($0.days) }
                }.fixedSize()
                Spacer()
                Button(model.hasScanned ? "Rescan" : "Scan") { Task { await model.scan() } }
                    .disabled(model.isScanning)
            }
            .padding(.horizontal, 24).padding(.bottom, 10)
            Divider()
            if model.isScanning {
                BusyMascot(title: "Scanning… \(model.scanned) files")
            } else if !model.hasScanned {
                Spacer(); Text("Choose filters and press Scan").foregroundStyle(.secondary); Spacer()
            } else if model.visible.isEmpty {
                Spacer(); Text("No matching files").foregroundStyle(.secondary); Spacer()
            } else {
                List(model.visible) { f in
                    Toggle(isOn: $model.selection.contains(f.url)) {
                        HStack(spacing: 10) {
                            FileIcon(url: f.url)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(f.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                                Text((f.url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                            }
                            Spacer()
                            Text(f.lastUsed.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption).foregroundStyle(.secondary)
                            Text(f.size.bytesString).monospacedDigit().frame(width: 80, alignment: .trailing)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .contextMenu {
                        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([f.url]) }
                    }
                }
            }
            BottomBar(text: model.isTrashing ? "Moving files to the Trash…"
                      : model.message ?? (model.hasScanned ? "\(model.selection.count) selected · \(model.selectedSize.bytesString)" : "")) {
                BusyButton(title: "Move to Trash", busyTitle: "Moving…", isBusy: model.isTrashing,
                           disabled: model.selectedFiles.isEmpty) { confirm = true }
            }
        }
        .alert("Move \(model.selectedFiles.count) file(s) to the Trash?", isPresented: $confirm) {
            Button("Move to Trash", role: .destructive) { Task { await model.trashSelected() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(model.selectedSize.bytesString) — you can still restore them from the Trash.")
        }
    }
}
