import SwiftUI

struct FirstRunSetupView: View {
    let model: AppModel

    @State private var step: SetupStep = .welcome

    init(model: AppModel) {
        self.model = model
        #if DEBUG
        let previewStep = ProcessInfo.processInfo.environment["KEYSWITCH_SETUP_STEP"]
            .flatMap(SetupStep.init(previewName:)) ?? .welcome
        _step = State(initialValue: previewStep)
        #endif
    }

    var body: some View {
        HStack(spacing: 0) {
            SetupSidebar(step: step, model: model)
                .frame(width: 206)

            Divider()
                .overlay(.white.opacity(0.06))

            VStack(spacing: 0) {
                SetupHeader(step: step) {
                    model.deferFirstRunSetup()
                }

                Divider()
                    .overlay(.white.opacity(0.05))

                Group {
                    switch step {
                    case .welcome:
                        WelcomeSetupPage(model: model)
                    case .permissions:
                        PermissionsSetupPage(model: model)
                    case .codex:
                        CodexSetupPage(model: model)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(step)
                .transition(.opacity.combined(with: .move(edge: .trailing)))

                Divider()
                    .overlay(.white.opacity(0.05))

                SetupFooter(
                    step: step,
                    primaryTitle: primaryButtonTitle,
                    showsProgress: model.codexRelaunchIsInProgress,
                    primaryDisabled: model.codexRelaunchIsInProgress,
                    onBack: moveBack,
                    onContinue: primaryAction
                )
            }
        }
        .frame(
            minWidth: 760,
            maxWidth: .infinity,
            minHeight: 610,
            maxHeight: .infinity
        )
        .background {
            SetupBackground()
                .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
        .onAppear {
            model.refreshPermissions()
        }
    }

    private var keyboardAccessIsReady: Bool {
        model.permissions.allGranted && model.eventTapIsActive
    }

    private var primaryButtonTitle: String {
        switch step {
        case .welcome:
            return "Get Started"
        case .permissions:
            if keyboardAccessIsReady {
                return "Continue"
            }
            if model.permissions.allGranted {
                return "Retry Keyboard Access"
            }
            return "Allow Keyboard Access"
        case .codex:
            if model.codexRelaunchIsInProgress {
                return "Reopening Codex…"
            }
            return model.bridgeStatus == .connected
                ? "Open Codex Micro Setup"
                : "Connect Codex"
        }
    }

    private func primaryAction() {
        switch step {
        case .welcome:
            move(to: .permissions)
        case .permissions:
            if keyboardAccessIsReady {
                move(to: .codex)
            } else {
                model.retryKeyboardAccess()
            }
        case .codex:
            if model.bridgeStatus == .connected {
                model.beginCodexMicroSetup()
            } else {
                model.connectCodexForSetup()
            }
        }
    }

    private func moveBack() {
        guard let previous = SetupStep(rawValue: step.rawValue - 1) else { return }
        move(to: previous)
    }

    private func move(to newStep: SetupStep) {
        withAnimation(.easeInOut(duration: 0.24)) {
            step = newStep
        }
    }
}

private enum SetupStep: Int, CaseIterable, Identifiable {
    case welcome
    case permissions
    case codex

    var id: Int { rawValue }

    var eyebrow: String {
        switch self {
        case .welcome: "WELCOME"
        case .permissions: "KEYBOARD ACCESS"
        case .codex: "CODEX MICRO"
        }
    }

    var sidebarTitle: String {
        switch self {
        case .welcome: "Welcome"
        case .permissions: "Permissions"
        case .codex: "Connect Codex"
        }
    }

    var sidebarIcon: String {
        switch self {
        case .welcome: "sparkles"
        case .permissions: "lock.shield.fill"
        case .codex: "cable.connector"
        }
    }

    init?(previewName: String) {
        switch previewName.lowercased() {
        case "welcome": self = .welcome
        case "permissions": self = .permissions
        case "codex": self = .codex
        default: return nil
        }
    }
}

private struct SetupBackground: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)

            LinearGradient(
                colors: [
                    Color(red: 0.075, green: 0.08, blue: 0.11).opacity(0.98),
                    Color(red: 0.035, green: 0.04, blue: 0.06).opacity(0.99),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [Color.setupPurple.opacity(0.18), .clear],
                center: UnitPoint(x: 0.12, y: 0.06),
                startRadius: 0,
                endRadius: 330
            )
        }
    }
}

private struct SetupSidebar: View {
    let step: SetupStep
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(.white.opacity(0.08))
                        .overlay {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(.white.opacity(0.13), lineWidth: 1)
                        }
                    Image(systemName: "keyboard.fill")
                        .font(.system(size: 17, weight: .semibold))
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 1) {
                    Text("KeySwitch")
                        .font(.system(size: 14, weight: .semibold))
                    Text("SETUP")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(1.4)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 42)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(SetupStep.allCases) { item in
                    SetupProgressRow(
                        item: item,
                        isCurrent: item == step,
                        isComplete: isComplete(item)
                    )

                    if item != SetupStep.allCases.last {
                        Rectangle()
                            .fill(connectorColor(after: item))
                            .frame(width: 1, height: 30)
                            .padding(.leading, 16)
                    }
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Label("About one minute", systemImage: "clock")
                Label("Editable anytime", systemImage: "slider.horizontal.3")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 22)
        .padding(.top, 34)
        .padding(.bottom, 24)
        .background(.black.opacity(0.12))
    }

    private func isComplete(_ item: SetupStep) -> Bool {
        switch item {
        case .welcome:
            step.rawValue > item.rawValue
        case .permissions:
            model.permissions.allGranted && model.eventTapIsActive
        case .codex:
            model.bridgeStatus == .connected
        }
    }

    private func connectorColor(after item: SetupStep) -> Color {
        step.rawValue > item.rawValue ? .green.opacity(0.55) : .white.opacity(0.1)
    }
}

private struct SetupProgressRow: View {
    let item: SetupStep
    let isCurrent: Bool
    let isComplete: Bool

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle()
                    .fill(indicatorFill)
                    .overlay {
                        Circle()
                            .stroke(indicatorStroke, lineWidth: 1)
                    }

                Image(systemName: isComplete ? "checkmark" : item.sidebarIcon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(indicatorForeground)
            }
            .frame(width: 33, height: 33)

            Text(item.sidebarTitle)
                .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                .foregroundStyle(isCurrent || isComplete ? .primary : .secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(isComplete ? "Complete" : isCurrent ? "Current step" : "Not started")
    }

    private var indicatorFill: Color {
        if isComplete { return .green.opacity(0.17) }
        if isCurrent { return Color.setupPurple.opacity(0.24) }
        return .white.opacity(0.04)
    }

    private var indicatorStroke: Color {
        if isComplete { return .green.opacity(0.5) }
        if isCurrent { return Color.setupPurple.opacity(0.75) }
        return .white.opacity(0.09)
    }

    private var indicatorForeground: Color {
        if isComplete { return .green }
        if isCurrent { return .white }
        return .secondary
    }
}

private struct SetupHeader: View {
    let step: SetupStep
    let onDefer: () -> Void

    var body: some View {
        HStack {
            Text("STEP \(step.rawValue + 1) OF \(SetupStep.allCases.count)  ·  \(step.eyebrow)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Set Up Later", action: onDefer)
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)
                .accessibilityHint("Closes setup without changing your configuration")
        }
        .padding(.horizontal, 30)
        .frame(height: 54)
    }
}

private struct WelcomeSetupPage: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 8)

            ZStack {
                Ellipse()
                    .fill(Color.setupPurple.opacity(0.18))
                    .blur(radius: 28)
                    .frame(width: 250, height: 120)

                MicroHUDView(
                    model: model,
                    continuousLightingMotionEnabled: model.configuration.animatedAgentLighting
                )
                    .scaleEffect(0.45)
                    .frame(width: 230, height: 174)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            VStack(spacing: 9) {
                Text("Your keyboard, rewired for Codex")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)

                Text("Hold your shortcut to turn familiar Mac keys into Codex Micro controls—then release it to return to normal typing.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 430)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                SetupFeaturePill(icon: "command", text: model.configuration.activationShortcut.displayName)
                SetupFeaturePill(icon: "person.3.fill", text: "6 Agent Keys")
                SetupFeaturePill(icon: "slider.horizontal.3", text: "Fully Editable")
            }

            Text("Your current Codex profile, tasks, and Micro settings stay in Codex.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 12)
    }
}

private struct SetupFeaturePill: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 11)
            .frame(height: 29)
            .background(.white.opacity(0.055), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.09), lineWidth: 1)
            }
    }
}

private struct PermissionsSetupPage: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SetupPageTitle(
                icon: "lock.shield.fill",
                title: "Allow keyboard access",
                detail: "KeySwitch needs two macOS permissions to listen for your activation shortcut and temporarily remap keys."
            )

            VStack(spacing: 10) {
                PermissionSetupRow(
                    icon: "keyboard",
                    title: "Input Monitoring",
                    detail: "Recognizes your shortcut and mapped key presses.",
                    granted: model.permissions.inputMonitoringGranted,
                    openSettings: PermissionService.openInputMonitoringSettings
                )

                PermissionSetupRow(
                    icon: "accessibility",
                    title: "Accessibility",
                    detail: "Suppresses normal typing while the layer is active.",
                    granted: model.permissions.accessibilityGranted,
                    openSettings: PermissionService.openAccessibilitySettings
                )
            }

            if model.permissions.allGranted && !model.eventTapIsActive {
                SetupNotice(
                    icon: "arrow.clockwise",
                    text: "Access is granted. Choose Retry Keyboard Access below to start keyboard capture.",
                    color: .orange
                )
            } else {
                SetupNotice(
                    icon: "hand.raised.fill",
                    text: "KeySwitch only remaps input while your activation shortcut is held or toggled on. Escape always turns the layer off.",
                    color: Color.setupPurple
                )
            }

            Spacer()
        }
        .padding(.horizontal, 36)
        .padding(.top, 34)
        .padding(.bottom, 22)
    }
}

private struct PermissionSetupRow: View {
    let icon: String
    let title: String
    let detail: String
    let granted: Bool
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(granted ? .green.opacity(0.12) : .white.opacity(0.05))
                Image(systemName: granted ? "checkmark" : icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(granted ? .green : .primary)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            if granted {
                Text("Granted")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
            } else {
                Button("Open Settings", action: openSettings)
                    .controlSize(.small)
                    .accessibilityHint("Opens the matching Privacy & Security page")
            }
        }
        .padding(.horizontal, 15)
        .frame(height: 70)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(granted ? .green.opacity(0.2) : .white.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct CodexSetupPage: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SetupPageTitle(
                icon: model.bridgeStatus == .connected ? "checkmark.circle.fill" : "cable.connector",
                iconColor: model.bridgeStatus == .connected ? .green : Color.setupPurple,
                title: model.bridgeStatus == .connected ? "Codex is connected" : "Connect the Codex app",
                detail: model.bridgeStatus == .connected
                    ? "KeySwitch can now open the official Codex Micro setup, where Codex owns your actions, agents, and keycaps."
                    : "The current compatibility connection must be enabled when Codex launches. KeySwitch can safely reopen your installed Codex app with it enabled."
            )

            CodexConnectionCard(model: model)

            if let message = model.setupErrorMessage {
                SetupNotice(
                    icon: "exclamationmark.triangle.fill",
                    text: message,
                    color: .orange
                )
            } else if model.bridgeStatus == .connected {
                SetupNotice(
                    icon: "checkmark.seal.fill",
                    text: "Connected to your normal Codex profile. No duplicate app or separate profile was created.",
                    color: .green
                )
            } else {
                SetupNotice(
                    icon: "info.circle.fill",
                    text: "Codex will close and reopen once. Your account, tasks, and settings are preserved.",
                    color: Color.setupPurple
                )
            }

            Spacer()
        }
        .padding(.horizontal, 36)
        .padding(.top, 34)
        .padding(.bottom, 22)
    }
}

private struct CodexConnectionCard: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 15) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.14))
                if model.codexRelaunchIsInProgress || model.bridgeStatus == .connecting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: statusIcon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(statusColor)
                }
            }
            .frame(width: 45, height: 45)

            VStack(alignment: .leading, spacing: 4) {
                Text(statusTitle)
                    .font(.system(size: 14, weight: .semibold))
                Text(statusDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .shadow(color: statusColor.opacity(0.7), radius: 5)
        }
        .padding(.horizontal, 17)
        .frame(height: 82)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(statusColor.opacity(0.24), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var statusColor: Color {
        switch model.bridgeStatus {
        case .connected: .green
        case .connecting: Color.setupPurple
        case .disconnected: .orange
        }
    }

    private var statusIcon: String {
        switch model.bridgeStatus {
        case .connected: "checkmark"
        case .connecting: "ellipsis"
        case .disconnected: "bolt.horizontal.circle"
        }
    }

    private var statusTitle: String {
        if model.codexRelaunchIsInProgress { return "Reopening Codex…" }
        return switch model.bridgeStatus {
        case .connected: "Connected"
        case .connecting: "Looking for Codex…"
        case .disconnected: "Ready to connect"
        }
    }

    private var statusDetail: String {
        if model.codexRelaunchIsInProgress { return "Waiting for the Codex window to become available" }
        return switch model.bridgeStatus {
        case .connected: "Official Micro setup is ready to open"
        case .connecting: "Checking the local Codex connection"
        case .disconnected: "Codex will reopen with local integration enabled"
        }
    }
}

private struct SetupPageTitle: View {
    let icon: String
    var iconColor: Color = Color.setupPurple
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(iconColor.opacity(0.14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(iconColor.opacity(0.25), lineWidth: 1)
                    }
                Image(systemName: icon)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text(detail)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SetupNotice: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .padding(.top, 1)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(13)
        .background(color.opacity(0.075), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(color.opacity(0.15), lineWidth: 1)
        }
    }
}

private struct SetupFooter: View {
    let step: SetupStep
    let primaryTitle: String
    let showsProgress: Bool
    let primaryDisabled: Bool
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if step != .welcome {
                Button("Back", action: onBack)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onContinue) {
                HStack(spacing: 8) {
                    if showsProgress {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(primaryTitle)
                        .fontWeight(.semibold)
                    if !showsProgress {
                        Image(systemName: step == .codex ? "arrow.up.forward.app" : "arrow.right")
                            .font(.system(size: 11, weight: .bold))
                    }
                }
                .frame(minWidth: 150)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Color.setupPurple)
            .disabled(primaryDisabled)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 30)
        .frame(height: 72)
    }
}

private extension Color {
    static let setupPurple = Color(red: 0.58, green: 0.48, blue: 0.94)
}
