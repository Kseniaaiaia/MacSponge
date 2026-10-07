import SwiftUI

/// Rounded "liquid glass" capsule. Falls back to a blurred material before macOS 26.
private struct GlassCapsule: ViewModifier {
    var tint: Color?
    var interactive = true
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(
                tint.map { Glass.regular.tint($0.opacity(0.85)).interactive(interactive) }
                    ?? Glass.regular.interactive(interactive),
                in: .capsule)
        } else {
            content
                .background(tint.map { AnyShapeStyle($0.gradient) } ?? AnyShapeStyle(.ultraThinMaterial), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
        }
    }
}

/// Main action: big, tinted glass pill.
struct PrimaryPillStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    var tint: Color = .accentColor
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 22).padding(.vertical, 10)
            .modifier(GlassCapsule(tint: tint))
            .opacity(enabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

/// Secondary action: smaller clear glass pill.
struct GlassPillStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .padding(.horizontal, 22).padding(.vertical, 10)
            .modifier(GlassCapsule(tint: nil))
            .opacity(enabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryPillStyle {
    static var primaryPill: PrimaryPillStyle { PrimaryPillStyle() }
}
extension ButtonStyle where Self == GlassPillStyle {
    static var glassPill: GlassPillStyle { GlassPillStyle() }
}

struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: ButtonStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

/// Rounded glass segmented control.
struct PillPicker<T: Hashable & Identifiable>: View {
    let options: [T]
    let label: (T) -> String
    @Binding var selection: T
    @Namespace private var ns
    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { o in
                Button { withAnimation(.spring(duration: 0.3)) { selection = o } } label: {
                    Text(label(o))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(selection == o ? .white : .primary)
                        .padding(.horizontal, 18).padding(.vertical, 8)
                        .background {
                            if selection == o {
                                Capsule().fill(Color.accentColor.gradient).matchedGeometryEffect(id: "sel", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .modifier(GlassCapsule(tint: nil, interactive: false))
    }
}

/// Rounded glass drop-down.
struct PillMenu<V: Hashable>: View {
    let title: String
    let options: [(label: String, value: V)]
    @Binding var selection: V
    var body: some View {
        Menu {
            ForEach(options, id: \.value) { o in
                Button { selection = o.value } label: {
                    if o.value == selection { Label(o.label, systemImage: "checkmark") } else { Text(o.label) }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(title).foregroundStyle(.secondary)
                Text(options.first { $0.value == selection }?.label ?? "").fontWeight(.semibold)
                Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .modifier(GlassCapsule(tint: nil))
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .fixedSize()
    }
}
