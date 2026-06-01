import Foundation
import Sparkle

@MainActor
final class SoftwareUpdateController {
    private let updaterController: SPUStandardUpdaterController?

    var updater: SPUUpdater? {
        updaterController?.updater
    }

    init() {
        // Sparkle may quit and relaunch the app; dsmn timer state must stay in
        // the helper store and must not be stopped or renewed by update code.
        guard Self.isConfigured else {
            updaterController = nil
            return
        }

        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
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
}
