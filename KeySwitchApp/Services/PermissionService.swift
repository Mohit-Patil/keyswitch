import AppKit
import ApplicationServices
import Foundation

struct PermissionSnapshot: Equatable {
    let inputMonitoringGranted: Bool
    let accessibilityGranted: Bool

    var allGranted: Bool {
        inputMonitoringGranted && accessibilityGranted
    }
}

enum KeyboardPermissionKind: CaseIterable, Equatable {
    case inputMonitoring
    case accessibility

    var title: String {
        switch self {
        case .inputMonitoring: "Input Monitoring"
        case .accessibility: "Accessibility"
        }
    }

    var settingsAnchor: String {
        switch self {
        case .inputMonitoring: "Privacy_ListenEvent"
        case .accessibility: "Privacy_Accessibility"
        }
    }

    func isGranted(in snapshot: PermissionSnapshot) -> Bool {
        switch self {
        case .inputMonitoring: snapshot.inputMonitoringGranted
        case .accessibility: snapshot.accessibilityGranted
        }
    }
}

enum PermissionService {
    static func snapshot() -> PermissionSnapshot {
        PermissionSnapshot(
            inputMonitoringGranted: CGPreflightListenEventAccess(),
            accessibilityGranted: AXIsProcessTrusted()
        )
    }

    static func request() {
        if !CGPreflightListenEventAccess() {
            _ = CGRequestListenEventAccess()
        }

        if !AXIsProcessTrusted() {
            // Use the documented option value directly. Referencing the
            // imported mutable CF global produces a Swift 6 data-race warning.
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
    }

    static func nextRequiredPermission(
        in snapshot: PermissionSnapshot
    ) -> KeyboardPermissionKind? {
        KeyboardPermissionKind.allCases.first { !$0.isGranted(in: snapshot) }
    }

    @MainActor
    static func openSettings(for kind: KeyboardPermissionKind) {
        openSystemSettings(anchor: kind.settingsAnchor)
        PermissionDragGuideController.shared.present(kind)
    }

    @MainActor
    static func openInputMonitoringSettings() {
        openSettings(for: .inputMonitoring)
    }

    @MainActor
    static func openAccessibilitySettings() {
        openSettings(for: .accessibility)
    }

    @MainActor
    static func dismissPermissionGuide() {
        PermissionDragGuideController.shared.dismiss()
    }

    @MainActor
    private static func openSystemSettings(anchor: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
