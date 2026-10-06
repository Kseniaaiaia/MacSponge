import SwiftUI
import RiveRuntime

/// Sponge mascot. Plays the first `.riv` found in the app bundle (Contents/Resources/*.riv);
/// until an animation exists it falls back to the static mascot picture.
/// Expects "State Machine 1" driven by the view-model Boolean `isScanning` (false → Idle, true → Dance).
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

/// Owns the Rive view model and the data-binding handle used to switch Idle ↔ Dance.
/// The animation is driven by the Boolean property `isScanning` of the default view model ("Main"),
/// not by a plain state-machine input.
@MainActor
private final class MascotController: ObservableObject {
    let rive: RiveViewModel
    private var setScanning: (Bool) -> Void = { _ in }

    init(fileName: String) {
        rive = RiveViewModel(fileName: fileName, stateMachineName: "State Machine 1", fit: .contain)
        guard let model = rive.riveModel,
              let viewModel = model.riveFile.defaultViewModel(for: model.artboard),
              let instance = viewModel.createDefaultInstance() else { return }
        model.stateMachine?.bind(viewModelInstance: instance)
        if let flag = instance.booleanProperty(fromPath: "isScanning") {
            setScanning = { flag.value = $0 }
        }
    }

    func set(scanning: Bool) { setScanning(scanning) }
}

private struct RiveMascot: View {
    let fileName: String
    let isScanning: Bool
    @StateObject private var controller: MascotController

    init(fileName: String, isScanning: Bool) {
        self.fileName = fileName
        self.isScanning = isScanning
        _controller = StateObject(wrappedValue: MascotController(fileName: fileName))
    }

    var body: some View {
        controller.rive.view()
            .onAppear { controller.set(scanning: isScanning) }
            .onChange(of: isScanning) { _, on in controller.set(scanning: on) }
    }
}

/// Mascot + caption, shown while something is being scanned or cleaned.
struct BusyMascot: View {
    let title: String
    var body: some View {
        VStack(spacing: 14) {
            MascotView(isScanning: true, size: 320)
            Text(title).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
