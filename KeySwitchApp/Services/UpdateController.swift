import AppKit
import Foundation
import Observation
import Security
import Sparkle

@MainActor
@Observable
final class UpdateStatus {
    var automaticUpdatesEnabled: Bool
    var isUpdateReady = false
    var availableVersion: String?

    init(automaticUpdatesEnabled: Bool) {
        self.automaticUpdatesEnabled = automaticUpdatesEnabled
    }
}

@MainActor
protocol UpdaterProviding: AnyObject {
    var isAvailable: Bool { get }
    var unavailableReason: String? { get }
    var currentVersion: String { get }
    var updateStatus: UpdateStatus { get }

    func setAutomaticUpdatesEnabled(_ enabled: Bool)
    func checkForUpdates(_ sender: Any?)
    func installUpdate()
}

@MainActor
final class DisabledUpdaterController: UpdaterProviding {
    let isAvailable = false
    let unavailableReason: String?
    let currentVersion: String
    let updateStatus = UpdateStatus(automaticUpdatesEnabled: false)

    init(
        reason: String,
        currentVersion: String = UpdateControllerFactory.currentVersion()
    ) {
        unavailableReason = reason
        self.currentVersion = currentVersion
    }

    func setAutomaticUpdatesEnabled(_ enabled: Bool) {
        _ = enabled
    }

    func checkForUpdates(_ sender: Any?) {
        _ = sender
    }

    func installUpdate() {}
}

/// Wraps Sparkle's prepared installation closure so it can safely cross from
/// the nonisolated delegate callback to the main actor.
final class PreparedUpdateAction: @unchecked Sendable {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    func install() {
        handler()
    }
}

@MainActor
final class SparkleUpdaterController: NSObject, UpdaterProviding, SPUUpdaterDelegate {
    static let automaticUpdatesDefaultsKey = "automaticUpdatesEnabled"

    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    let isAvailable = true
    let unavailableReason: String? = nil
    let currentVersion: String
    let updateStatus: UpdateStatus

    private let defaults: UserDefaults
    private var preparedUpdateAction: PreparedUpdateAction?

    init(
        savedAutomaticUpdates: Bool,
        currentVersion: String = UpdateControllerFactory.currentVersion(),
        defaults: UserDefaults = .standard,
        startingUpdater: Bool = true
    ) {
        self.currentVersion = currentVersion
        self.defaults = defaults
        updateStatus = UpdateStatus(automaticUpdatesEnabled: savedAutomaticUpdates)
        super.init()

        if startingUpdater {
            let updater = controller.updater
            updater.automaticallyChecksForUpdates = savedAutomaticUpdates
            updater.automaticallyDownloadsUpdates = savedAutomaticUpdates
            controller.startUpdater()
        }
    }

    func setAutomaticUpdatesEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.automaticUpdatesDefaultsKey)
        updateStatus.automaticUpdatesEnabled = enabled
        controller.updater.automaticallyChecksForUpdates = enabled
        controller.updater.automaticallyDownloadsUpdates = enabled
    }

    func checkForUpdates(_ sender: Any?) {
        controller.checkForUpdates(sender)
    }

    func installUpdate() {
        guard let preparedUpdateAction else {
            controller.checkForUpdates(nil)
            return
        }

        // Sparkle owns the replacement, termination, and relaunch sequence.
        // Keep the callback available in case application termination is
        // canceled and the user needs to invoke it again.
        preparedUpdateAction.install()
    }

    func prepareUpdateForInstallation(
        version: String,
        action: PreparedUpdateAction
    ) {
        preparedUpdateAction = action
        updateStatus.availableVersion = version
        updateStatus.isUpdateReady = true
    }

    func clearPreparedUpdate() {
        preparedUpdateAction = nil
        updateStatus.availableVersion = nil
        updateStatus.isUpdateReady = false
    }

    nonisolated func updater(
        _ updater: SPUUpdater,
        didDownloadUpdate item: SUAppcastItem
    ) {
        // A finished download is not yet guaranteed to have Sparkle's
        // prepared installation callback. Readiness is set only from
        // willInstallUpdateOnQuit below.
        _ = updater
        _ = item
    }

    nonisolated func updater(
        _ updater: SPUUpdater,
        failedToDownloadUpdate item: SUAppcastItem,
        error: Error
    ) {
        _ = updater
        _ = item
        _ = error
        Task { @MainActor in
            self.clearPreparedUpdate()
        }
    }

    nonisolated func userDidCancelDownload(_ updater: SPUUpdater) {
        _ = updater
        Task { @MainActor in
            self.clearPreparedUpdate()
        }
    }

    nonisolated func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        _ = updater
        let version = item.displayVersionString
        let action = PreparedUpdateAction(immediateInstallHandler)

        Task { @MainActor in
            self.prepareUpdateForInstallation(version: version, action: action)
        }
        return true
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        _ = updater
        _ = error
        Task { @MainActor in
            self.clearPreparedUpdate()
        }
    }

    nonisolated func updater(
        _ updater: SPUUpdater,
        userDidMake choice: SPUUserUpdateChoice,
        forUpdate updateItem: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        _ = updater
        let version = updateItem.displayVersionString
        let downloaded = state.stage == .downloaded

        Task { @MainActor in
            switch choice {
            case .install, .skip:
                self.clearPreparedUpdate()
            case .dismiss:
                self.updateStatus.availableVersion = downloaded ? version : nil
                self.updateStatus.isUpdateReady = downloaded && self.preparedUpdateAction != nil
            @unknown default:
                self.clearPreparedUpdate()
            }
        }
    }
}

@MainActor
enum UpdateControllerFactory {
    static func make(
        bundle: Bundle = .main,
        defaults: UserDefaults = .standard
    ) -> any UpdaterProviding {
        let version = currentVersion(bundle: bundle)

        #if DEBUG
        return DisabledUpdaterController(
            reason: "Updates are available in official release builds.",
            currentVersion: version
        )
        #else
        let bundleURL = bundle.bundleURL
        guard bundleURL.pathExtension == "app" else {
            return DisabledUpdaterController(
                reason: "Updates are unavailable in this build.",
                currentVersion: version
            )
        }

        if isHomebrewCask(appBundleURL: bundleURL) {
            return DisabledUpdaterController(
                reason: "This installation is managed by Homebrew. Use brew upgrade --cask keyswitch.",
                currentVersion: version
            )
        }

        guard isDeveloperIDSigned(bundleURL: bundleURL) else {
            return DisabledUpdaterController(
                reason: "Updates are available in Developer ID-signed release builds.",
                currentVersion: version
            )
        }

        let savedAutomaticUpdates =
            (defaults.object(forKey: SparkleUpdaterController.automaticUpdatesDefaultsKey) as? Bool)
            ?? true
        return SparkleUpdaterController(
            savedAutomaticUpdates: savedAutomaticUpdates,
            currentVersion: version,
            defaults: defaults
        )
        #endif
    }

    nonisolated static func currentVersion(bundle: Bundle = .main) -> String {
        let marketingVersion =
            bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "Unknown"
        guard let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              !build.isEmpty else {
            return marketingVersion
        }
        return "\(marketingVersion) (\(build))"
    }

    private static func isHomebrewCask(appBundleURL: URL) -> Bool {
        let path = appBundleURL.resolvingSymlinksInPath().path
        return path.contains("/Caskroom/") || path.contains("/Homebrew/Caskroom/")
    }

    private static func isDeveloperIDSigned(bundleURL: URL) -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(
            bundleURL as CFURL,
            SecCSFlags(),
            &staticCode
        ) == errSecSuccess,
        let staticCode else {
            return false
        }

        guard SecStaticCodeCheckValidity(
            staticCode,
            SecCSFlags(rawValue: kSecCSCheckAllArchitectures),
            nil
        ) == errSecSuccess else {
            return false
        }

        var signingInformation: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInformation
        ) == errSecSuccess,
        let information = signingInformation as? [String: Any],
        let certificates = information[kSecCodeInfoCertificates as String] as? [SecCertificate],
        let leafCertificate = certificates.first,
        let summary = SecCertificateCopySubjectSummary(leafCertificate) as String? else {
            return false
        }

        return summary.hasPrefix("Developer ID Application:")
    }
}
