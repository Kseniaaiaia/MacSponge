import SwiftUI
import RiveRuntime

/// Sponge mascot. Plays the first `.riv` found in the app bundle (Contents/Resources/*.riv);
/// until an animation exists it falls back to the static mascot picture.
/// Expects the state machine "State Machine 1" with a Bool input `isScanning` (Idle ↔ Dance).
struct MascotView: View {
    var isScanning: Bool = true
    var size: CGFloat = 180

    private static let rivURL = Bundle.main.urls(forResourcesWithExtension: "riv", subdirectory: nil)?.first
    private static let picture: NSImage? = Bundle.main.url(forResource: "mascot", withExtension: "png")
        .flatMap { NSImage(contentsOf: $0) }

    var body: some View {
        Group {
            if let url = Self.rivURL {
                RiveMascot(fileName: url.deletingPathExtension().lastPathComponent, isScanning: isScanning)
            } else if let img = Self.picture {
                Image(nsImage: img).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
            } else {
                Image(systemName: "sparkles").font(.system(size: size / 3)).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}

private struct RiveMascot: View {
    let fileName: String
    let isScanning: Bool
    @StateObject private var rive: RiveViewModel

    init(fileName: String, isScanning: Bool) {
        self.fileName = fileName
        self.isScanning = isScanning
        _rive = StateObject(wrappedValue: RiveViewModel(fileName: fileName, stateMachineName: "State Machine 1", fit: .contain))
    }

    var body: some View {
        rive.view()
            .onAppear { rive.setInput("isScanning", value: isScanning) }
            .onChange(of: isScanning) { _, on in rive.setInput("isScanning", value: on) }
    }
}

/// Mascot + caption, shown while something is being scanned or cleaned.
struct BusyMascot: View {
    let title: String
    var body: some View {
        VStack(spacing: 14) {
            MascotView(isScanning: true)
            Text(title).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
