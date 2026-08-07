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

    static func openInputMonitoringSettings() {
        openSystemSettings(anchor: "Privacy_ListenEvent")
    }

    static func openAccessibilitySettings() {
        openSystemSettings(anchor: "Privacy_Accessibility")
    }

    private static func openSystemSettings(anchor: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
