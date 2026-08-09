import AppKit
import ApplicationServices
import Foundation

struct PermissionSnapshot: Equatable {
    let accessibilityGranted: Bool

    var allGranted: Bool {
        accessibilityGranted
    }

    func keyboardAccessIsReady(eventTapIsActive: Bool) -> Bool {
        accessibilityGranted && eventTapIsActive
    }
}

enum KeyboardPermissionKind: CaseIterable, Equatable {
    case accessibility

    var title: String {
        "Accessibility"
    }

    var settingsAnchor: String {
        "Privacy_Accessibility"
    }

    func isGranted(in snapshot: PermissionSnapshot) -> Bool {
        snapshot.accessibilityGranted
    }
}

enum PermissionService {
    static func snapshot() -> PermissionSnapshot {
        // AXIsProcessTrusted() is cached per process on recent macOS releases
        // and can remain stale after the user changes the System Settings
        // switch. Creating a short-lived active event tap consults live TCC
        // state and tests the exact capability KeySwitch needs.
        PermissionSnapshot(
            accessibilityGranted: resolveAccessibilityGrant(
                cachedAPIValue: AXIsProcessTrusted(),
                eventTapProbeSucceeded: canCreateKeyboardEventTap()
            )
        )
    }

    static func resolveAccessibilityGrant(
        cachedAPIValue _: Bool,
        eventTapProbeSucceeded: Bool
    ) -> Bool {
        eventTapProbeSucceeded
    }

    private static func canCreateKeyboardEventTap() -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: permissionProbeEventCallback,
            userInfo: nil
        ) else {
            return false
        }

        CFMachPortInvalidate(tap)
        return true
    }

    static func request() {
        if !snapshot().accessibilityGranted {
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
        // Register the exact running bundle with TCC first. The drag tile is a
        // fallback for macOS versions that fail to add the app automatically.
        request()
        openSystemSettings(anchor: kind.settingsAnchor)
        PermissionDragGuideController.shared.present()
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

private func permissionProbeEventCallback(
    proxy _: CGEventTapProxy,
    type _: CGEventType,
    event: CGEvent,
    userInfo _: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    Unmanaged.passUnretained(event)
}
