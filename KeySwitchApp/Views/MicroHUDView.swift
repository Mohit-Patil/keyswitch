import AppKit
import Combine
import SwiftUI

struct MicroHUDOverlayView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expandedLightingMotionIsEnabled = false
    let model: AppModel

    private var expandedSideLength: CGFloat {
        model.effectiveExpandedHUDSize.sideLength
    }

    private var panelAnimation: Animation? {
        guard !reduceMotion else { return nil }
        return .smooth(duration: 0.16, extraBounce: 0)
    }

    private var isPresented: Bool {
        model.layerIsActive || model.hudPreviewIsVisible
    }

    var body: some View {
        let expandedLightingAnimationRequested = model.layerIsActive
            && model.configuration.animatedAgentLighting
            && !reduceMotion

        MicroHUDView(
            model: model,
            continuousLightingMotionEnabled: expandedLightingMotionIsEnabled
                && model.configuration.animatedAgentLighting
        )
        .scaleEffect(
            model.effectiveExpandedHUDSize.scale,
            anchor: .topTrailing
        )
        .opacity(isPresented ? 1 : 0)
        .animation(panelAnimation, value: isPresented)
        .frame(
            width: expandedSideLength,
            height: expandedSideLength,
            alignment: .topTrailing
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            model.layerIsActive ? "KeySwitch layer active" : "Codex Micro size preview"
        )
        .accessibilityHidden(!isPresented)
        .task(id: expandedLightingAnimationRequested) {
            expandedLightingMotionIsEnabled = false
            guard expandedLightingAnimationRequested else { return }

            // Let the frosted surface finish compositing before resuming the
            // continuously animated agent rims. The task is automatically
            // cancelled if the layer closes during the transition.
            try? await Task.sleep(nanoseconds: 160_000_000)
            guard !Task.isCancelled else { return }
            expandedLightingMotionIsEnabled = true
        }
    }
}

@MainActor
private final class HUDAgentLightingClock: ObservableObject {
    @Published private(set) var date: Date?
    private var clockTask: Task<Void, Never>?

    func setActive(_ active: Bool) {
        guard active != (clockTask != nil) else { return }

        clockTask?.cancel()
        clockTask = nil

        guard active else {
            date = nil
            return
        }

        date = Date()
        clockTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 33_333_333)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                self?.date = Date()
            }
        }
    }

    deinit {
        clockTask?.cancel()
    }
}

struct MicroHUDView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var inheritedColorScheme
    // @State owns the stable reference without subscribing this parent view
    // to the clock's ObservableObject publications. Only the lighting leaves
    // below use @ObservedObject.
    @State private var lightingClock = HUDAgentLightingClock()
    let model: AppModel
    var continuousLightingMotionEnabled = false
    var onSelectControl: ((MicroControl) -> Void)? = nil

    private let keySize: CGFloat = 78
    private let spacing: CGFloat = 9

    private var lightingAnimationIsActive: Bool {
        guard continuousLightingMotionEnabled, !reduceMotion else { return false }
        return (0..<6).contains { slot in
            let light = model.lightingSnapshot.light(for: slot)
            return light.selected || light.status == .working
        }
    }

    var body: some View {
        // The one shared clock is observed only by HUDAgentLighting leaves,
        // so its 30 Hz opt-in updates do not invalidate the chassis, command
        // rows, dial, or analog stick.
        hudGrid
        .padding(15)
        .frame(width: 384, height: 384)
        .background {
            HUDChassisView()
        }
        // Keep the preview's HUD appearance local. preferredColorScheme
        // propagates upward to the enclosing presentation, which would make
        // the entire Settings window adopt the HUD's Light or Dark choice.
        .environment(
            \.colorScheme,
            model.effectiveHUDAppearance.colorScheme ?? inheritedColorScheme
        )
        .accessibilityElement(children: .contain)
        .onAppear {
            lightingClock.setActive(lightingAnimationIsActive)
        }
        .onChange(of: lightingAnimationIsActive) { _, active in
            lightingClock.setActive(active)
        }
        .onDisappear {
            lightingClock.setActive(false)
        }
    }

    private var hudGrid: some View {
        VStack(spacing: spacing) {
            HStack(spacing: spacing) {
                HUDSelectableSurface(action: selectionAction(for: .dialPress)) {
                    HUDKnobView(
                        step: model.dialRotationStep,
                        isPressed: model.pressedControls.contains(.dialPress),
                        previousKey: accessibilityKeyName(for: .dialPrevious),
                        nextKey: accessibilityKeyName(for: .dialNext),
                        pressKey: accessibilityKeyName(for: .dialPress)
                    )
                }
                    .frame(width: keySize, height: keySize)
                key(.agent0)
                key(.agent1)
                HUDSelectableSurface(action: selectionAction(for: .stickUp)) {
                    HUDAnalogStickView(model: model)
                }
                    .frame(width: keySize, height: keySize)
            }

            HStack(spacing: spacing) {
                key(.agent2)
                key(.agent3)
                key(.agent4)
                key(.agent5)
            }

            HStack(spacing: spacing) {
                key(.fastMode)
                key(.approve)
                key(.reject)
                key(.fork)
            }

            HStack(spacing: spacing) {
                HUDConnectionSelectorView(status: model.bridgeStatus)
                    .frame(width: keySize, height: keySize)
                if model.codexMicroLayout.separateMicrophoneKeys {
                    key(.pushToTalk)
                    key(.pushToTalkSecondary)
                } else {
                    key(.pushToTalk, width: keySize * 2 + spacing)
                }
                key(.submit)
            }
        }
    }

    private func selectionAction(for control: MicroControl) -> (() -> Void)? {
        guard let onSelectControl else { return nil }
        return { onSelectControl(control) }
    }

    private func key(
        _ control: MicroControl,
        width: CGFloat? = nil
    ) -> some View {
        HUDKeyView(
            model: model,
            control: control,
            size: keySize,
            width: width,
            lightingClock: lightingClock,
            onSelect: selectionAction(for: control)
        )
    }

    private func accessibilityKeyName(for control: MicroControl) -> String {
        model.binding(for: control).physicalKey?.displayName ?? "Not mapped"
    }
}

private struct HUDSelectableSurface<Content: View>: View {
    let action: (() -> Void)?
    @ViewBuilder let content: () -> Content
    @State private var isHovered = false

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    content()
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { isHovered = $0 }
            } else {
                content()
            }
        }
        .overlay {
            if action != nil, isHovered {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.9), lineWidth: 2)
                    .shadow(color: Color.accentColor.opacity(0.45), radius: 8)
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct HUDChassisView: View {
    @Environment(\.colorScheme) private var colorScheme
    private let shape = RoundedRectangle(cornerRadius: 25, style: .continuous)

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        ZStack {
            HUDActiveVisualEffectView()

            Group {
                if isDark {
                    Color(red: 0.025, green: 0.028, blue: 0.035)
                        .opacity(0.56)
                } else {
                    Color(red: 0.22, green: 0.235, blue: 0.27)
                        .opacity(0.44)
                }
            }

            LinearGradient(
                colors: isDark
                    ? [.white.opacity(0.045), .clear, .black.opacity(0.28)]
                    : [.white.opacity(0.22), .white.opacity(0.035), .black.opacity(0.24)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: isDark
                    ? [.white.opacity(0.085), .white.opacity(0.02), .clear]
                    : [.white.opacity(0.16), .white.opacity(0.025), .clear],
                center: UnitPoint(x: 0.5, y: 0.42),
                startRadius: 0,
                endRadius: 205
            )

            RadialGradient(
                colors: [.clear, .black.opacity(isDark ? 0.36 : 0.24)],
                center: .center,
                startRadius: 125,
                endRadius: 270
            )
        }
        .clipShape(shape)
        .overlay {
            shape
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(isDark ? 0.115 : 0.46),
                            .white.opacity(isDark ? 0.03 : 0.08),
                            .black.opacity(isDark ? 0.6 : 0.42),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(isDark ? 0.035 : 0.14), lineWidth: 0.75)
                .padding(3)
        }
    }
}

private struct HUDActiveVisualEffectView: NSViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        configure(view)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        configure(view)
    }

    private func configure(_ view: NSVisualEffectView) {
        view.material = colorScheme == .dark ? .hudWindow : .popover
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = true
    }
}

private enum HUDKeyTone {
    case frosted
    case dark
}

private struct HUDGlassKeySurface: View {
    @Environment(\.colorScheme) private var colorScheme
    let tone: HUDKeyTone
    let isPressed: Bool

    private var isDark: Bool { colorScheme == .dark }

    private var tint: LinearGradient {
        if isPressed {
            return LinearGradient(
                colors: [Color.hudPurple.opacity(0.64), Color.hudPurple.opacity(0.27)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        if !isDark {
            switch tone {
            case .frosted:
                return LinearGradient(
                    colors: [
                        Color(red: 0.64, green: 0.66, blue: 0.71).opacity(0.72),
                        Color(red: 0.42, green: 0.44, blue: 0.5).opacity(0.76),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .dark:
                return LinearGradient(
                    colors: [
                        Color(red: 0.56, green: 0.58, blue: 0.63).opacity(0.76),
                        Color(red: 0.35, green: 0.37, blue: 0.42).opacity(0.8),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }

        switch tone {
        case .frosted:
            return LinearGradient(
                colors: [
                    Color(red: 0.48, green: 0.49, blue: 0.54).opacity(0.34),
                    Color(red: 0.22, green: 0.24, blue: 0.29).opacity(0.46),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .dark:
            return LinearGradient(
                colors: [
                    Color(red: 0.13, green: 0.14, blue: 0.17).opacity(0.42),
                    Color(red: 0.035, green: 0.04, blue: 0.055).opacity(0.6),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(tint)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(isDark ? (tone == .frosted ? 0.35 : 0.2) : 0.52),
                                .white.opacity(isDark ? 0.055 : 0.08),
                                .black.opacity(isDark ? 0.54 : 0.38),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.25
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(
                        .white.opacity(isDark ? (tone == .frosted ? 0.1 : 0.05) : 0.18),
                        lineWidth: 0.75
                    )
                    .padding(3)
            }
            .shadow(color: .black.opacity(isDark ? 0.48 : 0.32), radius: 5, y: 4)
            .shadow(
                color: .white.opacity(isDark ? (tone == .frosted ? 0.1 : 0.035) : 0.18),
                radius: 1,
                y: -1
            )
    }
}

private struct HUDKeyView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    let model: AppModel
    let control: MicroControl
    let size: CGFloat
    var width: CGFloat? = nil
    let lightingClock: HUDAgentLightingClock
    var onSelect: (() -> Void)? = nil
    @State private var isHovered = false

    private var isPressed: Bool {
        model.pressedControls.contains(control)
    }

    private var physicalKeyName: String {
        model.binding(for: control).physicalKey?.displayName ?? "—"
    }

    private var tone: HUDKeyTone {
        control.slot == nil ? .dark : .frosted
    }

    private var agentLight: AgentLightState? {
        model.light(for: control)
    }

    private var pressGlowColor: Color {
        guard let agentLight, agentLight.status != .off else { return .hudPurple }
        return Color(packedRGB: agentLight.status.packedRGB)
    }

    private var foregroundColor: Color {
        guard colorScheme == .light else { return .white.opacity(0.97) }
        guard let agentLight else { return .black.opacity(0.78) }
        switch agentLight.status {
        case .off, .idle:
            return .black.opacity(0.72)
        case .working, .unread, .awaitingApproval, .awaitingResponse, .error:
            return .white.opacity(0.97)
        }
    }

    private var keyContent: some View {
        ZStack {
            HUDGlassKeySurface(tone: tone, isPressed: isPressed)

            if let agentLight {
                HUDAgentLighting(
                    animationClock: lightingClock,
                    state: agentLight,
                    brightness: model.effectiveLightingBrightness,
                    isPressed: isPressed
                )
            } else {
                HUDControlGlyph(
                    control: control,
                    keycap: control.supportsKeycapAppearance ? model.keycap(for: control) : nil,
                    foregroundColor: foregroundColor
                )
            }

            Text(physicalKeyName)
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundStyle(foregroundColor.opacity(colorScheme == .dark ? 0.49 : 0.64))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .padding(.horizontal, 7)
                .padding(.bottom, 6)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(width: width ?? size, height: size)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    var body: some View {
        Group {
            if let onSelect {
                Button(action: onSelect) {
                    keyContent
                }
                .buttonStyle(.plain)
                .onHover { isHovered = $0 }
            } else {
                keyContent
            }
        }
        .overlay {
            if onSelect != nil, isHovered {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.95), lineWidth: 2)
                    .shadow(color: Color.accentColor.opacity(0.5), radius: 9)
                    .allowsHitTesting(false)
            }
        }
        .scaleEffect(isPressed ? 0.955 : 1)
        .shadow(color: isPressed ? pressGlowColor.opacity(0.48) : .clear, radius: 12)
        .animation(
            reduceMotion ? nil : .spring(response: 0.16, dampingFraction: 0.74),
            value: isPressed
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(control.title)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(onSelect == nil ? [] : .isButton)
    }

    private var accessibilityValue: String {
        let mapping = model.binding(for: control).physicalKey.map {
            "Mapped to \($0.displayName)"
        } ?? "Not mapped"
        guard let agentLight else { return mapping }

        var details: [String] = []
        if let title = agentLight.title {
            details.append(title)
        }
        details.append(agentLight.status.title)
        if agentLight.selected {
            details.append("Selected")
        }
        details.append(mapping)
        return details.joined(separator: ", ")
    }
}

private struct HUDControlGlyph: View {
    let control: MicroControl
    let keycap: MicroKeycap?
    let foregroundColor: Color

    @ViewBuilder
    var body: some View {
        if let keycap {
            MicroKeycapGlyph(keycap: keycap, size: 29)
                .foregroundStyle(foregroundColor)
                .offset(y: -2)
        } else {
            Image(systemName: control.systemImage)
                .font(.system(size: 27, weight: .medium))
                .foregroundStyle(foregroundColor)
                .offset(y: -2)
        }
    }
}

private struct HUDAgentPalette {
    let surfaceTop: Color
    let surfaceBottom: Color
    let rim: Color
    let glow: Color

    static let switchHighlight = Color(packedRGB: 0xC7C0EF)
    static let switchLavender = Color(packedRGB: 0xAFA6D9)
    static let switchShadow = Color(packedRGB: 0x8580B5)

    init(status: AgentLightStatus, colorScheme: ColorScheme) {
        switch status {
        case .off:
            if colorScheme == .dark {
                surfaceTop = Color(packedRGB: 0x626570)
                surfaceBottom = Color(packedRGB: 0x3F424C)
                rim = Color(packedRGB: 0x747782)
            } else {
                surfaceTop = Color(packedRGB: 0xC3C6CD)
                surfaceBottom = Color(packedRGB: 0x9499A3)
                rim = Color(packedRGB: 0xD9DBE0)
            }
            glow = .clear
        case .idle:
            if colorScheme == .dark {
                surfaceTop = Color(packedRGB: 0xE6E6E9)
                surfaceBottom = Color(packedRGB: 0xBEC0C7)
                rim = Color(packedRGB: 0xEEEEF1)
            } else {
                surfaceTop = Color(packedRGB: 0xD0D2D7)
                surfaceBottom = Color(packedRGB: 0xA7ABB3)
                rim = Color(packedRGB: 0xE0E1E4)
            }
            glow = Color(packedRGB: status.packedRGB)
        case .working:
            surfaceTop = Color(packedRGB: 0x4D66E1)
            surfaceBottom = Color(packedRGB: 0x3048C3)
            rim = Color(packedRGB: 0x7187EC)
            glow = Color(packedRGB: status.packedRGB)
        case .unread:
            surfaceTop = Color(packedRGB: 0x74DD78)
            surfaceBottom = Color(packedRGB: 0x4BC46B)
            rim = Color(packedRGB: 0x94E999)
            glow = Color(packedRGB: status.packedRGB)
        case .awaitingApproval, .awaitingResponse:
            surfaceTop = Color(packedRGB: 0xE2884E)
            surfaceBottom = Color(packedRGB: 0xB95626)
            rim = Color(packedRGB: 0xF09C67)
            glow = Color(packedRGB: status.packedRGB)
        case .error:
            surfaceTop = Color(packedRGB: 0xEB5563)
            surfaceBottom = Color(packedRGB: 0xBC293C)
            rim = Color(packedRGB: 0xF47884)
            glow = Color(packedRGB: status.packedRGB)
        }
    }
}

private struct HUDAgentLighting: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var animationClock: HUDAgentLightingClock
    let state: AgentLightState
    let brightness: Double
    let isPressed: Bool

    private var signalColor: Color {
        Color(packedRGB: state.status.packedRGB)
    }

    private var palette: HUDAgentPalette {
        HUDAgentPalette(status: state.status, colorScheme: colorScheme)
    }

    private var normalizedBrightness: Double {
        min(max(brightness, 0), 1)
    }

    private var shouldOrbit: Bool {
        state.selected || state.status == .working
    }

    private var shouldAnimate: Bool {
        shouldOrbit && animationClock.date != nil
    }

    var body: some View {
        let pulse = pulseAmount(at: animationClock.date)
        let orbit = orbitDegrees(at: animationClock.date)

        ZStack {
            if state.status != .off {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [palette.surfaceTop, palette.surfaceBottom],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .opacity(
                        (0.82 + 0.12 * normalizedBrightness)
                            * normalizedBrightness
                            * pulse
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.42),
                                        palette.rim.opacity(0.82),
                                        .black.opacity(0.34),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: state.selected ? 1.6 : 1.2
                            )
                            .opacity(normalizedBrightness * pulse)
                    }
                    .shadow(
                        color: palette.glow.opacity(
                            (isPressed ? 0.72 : 0.38) * normalizedBrightness * pulse
                        ),
                        radius: state.selected ? 13 : 8
                    )

                if shouldOrbit {
                    HUDAgentOrbitingRim(
                        color: signalColor,
                        phase: orbit,
                        brightness: normalizedBrightness,
                        emphasized: state.selected,
                        isPressed: isPressed
                    )
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.18),
                                    palette.rim.opacity(0.3 * normalizedBrightness),
                                    .clear,
                                    .black.opacity(0.18),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                        .padding(2)
                }
            }

            lightDot(pulse: pulse)
        }
    }

    private func lightDot(pulse: Double) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        .white.opacity(isPressed ? 0.58 : 0.38),
                        HUDAgentPalette.switchHighlight,
                        HUDAgentPalette.switchLavender,
                        HUDAgentPalette.switchShadow,
                    ],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 13
                )
            )
            .frame(width: 19, height: 19)
            .overlay {
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.34), .black.opacity(0.24)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(0.38), radius: 3, y: 2)
            .shadow(
                color: HUDAgentPalette.switchLavender.opacity(
                    (state.selected ? 0.48 : 0.28) * (0.82 + 0.18 * pulse)
                ),
                radius: state.selected ? 7 : 4
            )
    }

    private func pulseAmount(at date: Date?) -> Double {
        guard shouldAnimate, let date else { return 1 }
        let wave = (sin(date.timeIntervalSinceReferenceDate * .pi * 1.25) + 1) / 2
        return 0.8 + wave * 0.2
    }

    private func orbitDegrees(at date: Date?) -> Double {
        guard shouldAnimate, let date else { return 0 }
        let duration = state.status == .working ? 2.8 : 4.2
        let progress = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: duration) / duration
        return progress * 360
    }
}

private struct HUDAgentOrbitingRim: View {
    let color: Color
    let phase: Double
    let brightness: Double
    let emphasized: Bool
    let isPressed: Bool

    private var rimGradient: AngularGradient {
        AngularGradient(
            gradient: Gradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: 0.54),
                .init(color: color.opacity(0.08), location: 0.62),
                .init(color: color.opacity(0.5), location: 0.73),
                .init(color: .white.opacity(0.96), location: 0.81),
                .init(color: color.opacity(0.86), location: 0.86),
                .init(color: color.opacity(0.2), location: 0.93),
                .init(color: .clear, location: 1),
            ]),
            center: .center,
            angle: .degrees(phase)
        )
    }

    private var highlightCenter: UnitPoint {
        let radians = (phase - 90) * .pi / 180
        return UnitPoint(
            x: 0.5 + CGFloat(cos(radians)) * 0.43,
            y: 0.5 + CGFloat(sin(radians)) * 0.43
        )
    }

    private var intensity: Double {
        (0.38 + brightness * 0.62) * (isPressed ? 1.18 : 1)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    rimGradient,
                    lineWidth: emphasized ? 5.5 : 4.5
                )
                .blur(radius: emphasized ? 5 : 4)
                .opacity(0.72 * intensity)

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    rimGradient,
                    lineWidth: emphasized ? 2.4 : 1.9
                )
                .opacity(0.94 * intensity)
                .shadow(
                    color: color.opacity(0.7 * intensity),
                    radius: emphasized ? 4 : 3
                )

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [
                            .white.opacity(0.2 * intensity),
                            color.opacity(0.1 * intensity),
                            .clear,
                        ],
                        center: highlightCenter,
                        startRadius: 0,
                        endRadius: emphasized ? 42 : 36
                    )
                )
                .padding(2)
                .blendMode(.screen)

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.15 * intensity),
                            .clear,
                            color.opacity(0.13 * intensity),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.75
                )
                .padding(2)
        }
        .allowsHitTesting(false)
    }
}

private extension Color {
    init(packedRGB: UInt32) {
        self.init(
            red: Double((packedRGB >> 16) & 0xFF) / 255,
            green: Double((packedRGB >> 8) & 0xFF) / 255,
            blue: Double(packedRGB & 0xFF) / 255
        )
    }
}

private extension HUDAppearance {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

private struct HUDKnobView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    let step: Int
    let isPressed: Bool
    let previousKey: String
    let nextKey: String
    let pressKey: String

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        Circle()
            .fill(.thinMaterial)
            .overlay {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(
                                    red: isDark ? 0.12 : 0.5,
                                    green: isDark ? 0.13 : 0.52,
                                    blue: isDark ? 0.16 : 0.58
                                ).opacity(0.98),
                                Color(
                                    red: isDark ? 0.13 : 0.28,
                                    green: isDark ? 0.14 : 0.3,
                                    blue: isDark ? 0.18 : 0.36
                                ).opacity(0.96),
                                Color(
                                    red: isDark ? 0.29 : 0.68,
                                    green: isDark ? 0.3 : 0.69,
                                    blue: isDark ? 0.35 : 0.73
                                ).opacity(0.92),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(isDark ? 0.16 : 0.42),
                                .black.opacity(isDark ? 0.56 : 0.38),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
            }
            .overlay {
                ZStack {
                    Capsule()
                        .fill(
                            isPressed
                                ? Color.hudPurple
                                : (isDark ? Color.white.opacity(0.3) : Color.black.opacity(0.3))
                        )
                        .frame(width: 3, height: 12)
                        .offset(y: -23)
                        .shadow(
                            color: isPressed ? Color.hudPurple.opacity(0.75) : .clear,
                            radius: 5
                        )
                }
                .rotationEffect(.degrees(Double(step % 8) * 45))
            }
            .padding(5)
            .scaleEffect(isPressed ? 0.94 : 1)
            .shadow(color: .black.opacity(isDark ? 0.52 : 0.34), radius: 5, y: 4)
            .animation(
                reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.72),
                value: step
            )
            .animation(
                reduceMotion ? nil : .spring(response: 0.16, dampingFraction: 0.76),
                value: isPressed
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Dial")
            .accessibilityValue(
                "Position \(step + 1) of 8. Previous mapped to \(previousKey). "
                    + "Next mapped to \(nextKey). Press mapped to \(pressKey)"
            )
    }
}

private struct HUDAnalogStickView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    let model: AppModel

    private var isDark: Bool { colorScheme == .dark }

    private var offset: CGSize {
        var x: CGFloat = 0
        var y: CGFloat = 0

        if model.pressedControls.contains(.stickLeft) { x -= 8 }
        if model.pressedControls.contains(.stickRight) { x += 8 }
        if model.pressedControls.contains(.stickUp) { y -= 8 }
        if model.pressedControls.contains(.stickDown) { y += 8 }

        return CGSize(width: x, height: y)
    }

    private var isPressed: Bool {
        offset != .zero
    }

    private var accessibilityValue: String {
        let position = isPressed ? "Moved" : "Centered"
        let mappings: [MicroControl] = [.stickUp, .stickRight, .stickDown, .stickLeft]
        let mappingSummary = mappings.map { control in
            let key = model.binding(for: control).physicalKey?.displayName ?? "Not mapped"
            return "\(control.title) mapped to \(key)"
        }.joined(separator: ". ")
        return "\(position). \(mappingSummary)"
    }

    var body: some View {
        ZStack {
            HUDGlassKeySurface(tone: .dark, isPressed: isPressed)

            Circle()
                .fill(
                    RadialGradient(
                        colors: isDark
                            ? [Color(red: 0.055, green: 0.06, blue: 0.07), .black]
                            : [Color(red: 0.52, green: 0.54, blue: 0.6),
                               Color(red: 0.24, green: 0.25, blue: 0.29)],
                        center: .topLeading,
                        startRadius: 1,
                        endRadius: 28
                    )
                )
                .frame(width: 48, height: 48)
                .overlay {
                    Circle()
                        .stroke(.white.opacity(isDark ? 0.055 : 0.34), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.72), radius: 5, y: 3)
                .offset(offset)
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.15, dampingFraction: 0.7),
            value: offset
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Analog stick")
        .accessibilityValue(accessibilityValue)
    }
}

private struct HUDConnectionSelectorView: View {
    @Environment(\.colorScheme) private var colorScheme
    let status: BridgeStatus

    private var isDark: Bool { colorScheme == .dark }

    private var statusColor: Color {
        switch status {
        case .connected:
            Color(red: 0.48, green: 0.66, blue: 0.98)
        case .connecting:
            Color(red: 0.9, green: 0.72, blue: 0.34)
        case .disconnected:
            Color(red: 0.46, green: 0.47, blue: 0.52)
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            VStack(spacing: 4) {
                Circle()
                    .fill(statusColor)
                Circle()
                    .fill(Color(red: 0.88, green: 0.88, blue: 0.72).opacity(0.76))
                Circle()
                    .fill(Color(red: 0.8, green: 0.8, blue: 0.48).opacity(0.76))
            }
            .frame(width: 6)
            .shadow(color: statusColor.opacity(status == .connected ? 0.7 : 0.25), radius: 4)

            Circle()
                .fill(.thinMaterial)
                .overlay {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(
                                        red: isDark ? 0.13 : 0.5,
                                        green: isDark ? 0.14 : 0.52,
                                        blue: isDark ? 0.17 : 0.58
                                    ).opacity(0.98),
                                    Color(
                                        red: isDark ? 0.08 : 0.25,
                                        green: isDark ? 0.09 : 0.27,
                                        blue: isDark ? 0.12 : 0.32
                                    ).opacity(0.98),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay {
                    Circle().stroke(.white.opacity(isDark ? 0.055 : 0.22), lineWidth: 1)
                }
                .frame(width: 52, height: 52)
                .shadow(color: .black.opacity(isDark ? 0.6 : 0.36), radius: 5, y: 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Codex connection")
        .accessibilityValue(status.title)
    }
}

private extension Color {
    static let hudPurple = Color(red: 0.58, green: 0.48, blue: 0.94)
}
