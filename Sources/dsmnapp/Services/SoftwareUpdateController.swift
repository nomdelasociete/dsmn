import AppKit
import Foundation
import Sparkle

@MainActor
final class SoftwareUpdateController: NSObject, SPUUpdaterDelegate {
    private var updaterController: SPUStandardUpdaterController?
    private var isPresentingRecoveryAlert = false

    var updater: SPUUpdater? {
        updaterController?.updater
    }

    override init() {
        // Sparkle may quit and relaunch the app; dsmn timer state must stay in
        // the helper store and must not be stopped or renewed by update code.
        super.init()

        guard Self.isConfigured else {
            return
        }

        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        guard Self.isRecoverableInstallationError(error), !isPresentingRecoveryAlert else {
            return
        }

        isPresentingRecoveryAlert = true
        defer {
            isPresentingRecoveryAlert = false
        }

        showInstallationRecoveryAlert(updater: updater)
    }

    private static var isConfigured: Bool {
        configuredValue(for: "SUFeedURL") != nil &&
            configuredValue(for: "SUPublicEDKey") != nil
    }

    private static func configuredValue(for key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else {
            return nil
        }

        return trimmed
    }

    private static func isRecoverableInstallationError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == SUSparkleErrorDomain else {
            return false
        }

        return [
            Int(SUError.fileCopyFailure.rawValue),
            Int(SUError.authenticationFailure.rawValue),
            Int(SUError.installationError.rawValue),
            Int(SUError.installationWriteNoPermissionError.rawValue)
        ].contains(nsError.code)
    }

    private func showInstallationRecoveryAlert(updater: SPUUpdater) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "macOS blocked the update"
        alert.informativeText = """
        dsmn could not replace the app in Applications.

        Approve the macOS permission prompt and retry the update. If macOS keeps blocking it, download the latest DMG and drag dsmn into Applications.

        Your current dsmn timer is kept as-is.
        """
        alert.addButton(withTitle: "Retry Update")
        alert.addButton(withTitle: "Download DMG")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            updater.checkForUpdates()
        case .alertSecondButtonReturn:
            if let url = URL(string: "https://dsmn.app/download/dsmn-latest.dmg") {
                NSWorkspace.shared.open(url)
            }
        default:
            break
        }
    }
}
