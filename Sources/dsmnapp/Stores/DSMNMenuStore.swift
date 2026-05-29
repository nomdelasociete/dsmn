import DSMNCore
import Foundation

@MainActor
final class DSMNMenuStore: ObservableObject {
    @Published private(set) var report: StatusReport?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var helperStatus: HelperRegistrationStatus = .notFound

    private let controller: DSMNController?
    private let helper = HelperServiceClient()
    private let setupError: Error?
    private var refreshLoopTask: Task<Void, Never>?

    init() {
        do {
            let store = try StateStore.defaultStore()
            controller = DSMNController(store: store)
            setupError = nil
        } catch {
            controller = nil
            setupError = error
            errorMessage = error.localizedDescription
        }
    }

    var menuBarIconState: MenuBarIconState {
        MenuBarIconState.resolve(report: report, errorMessage: errorMessage)
    }

    var menuBarSystemImage: String {
        menuBarIconState.systemImageName
    }

    var statusLine: String {
        guard let report else {
            return errorMessage ?? "Loading"
        }

        if report.decision.shouldPreventSleep && !report.state.ownsSleepDisable {
            return helperStatus == .enabled ? "Applying" : "Helper required"
        }

        if report.decision.shouldPreventSleep {
            if let remaining = report.state.manualRemainingSeconds(at: Date()), remaining > 0 {
                return "Active - \(formatDuration(remaining))"
            }

            return "Active"
        }

        return "Off"
    }

    var helperStatusLine: String {
        "Helper: \(helperStatus.displayName)"
    }

    func menuBarCountdownText(at date: Date = Date()) -> String? {
        MenuBarCountdownFormatter.text(report: report, at: date)
    }

    func menuBarAccessibilityLabel(at date: Date = Date()) -> String {
        if let countdown = menuBarCountdownText(at: date) {
            return "Active, \(countdown) remaining"
        }

        return statusLine
    }

    var setupLine: String? {
        switch helperStatus {
        case .notRegistered, .notFound:
            "Setup: install helper"
        case .requiresApproval:
            "Setup: approve Login Items"
        case .enabled:
            if let report, report.decision.shouldPreventSleep && !report.state.ownsSleepDisable {
                "Power lock: pending"
            } else {
                nil
            }
        }
    }

    var powerLockLine: String? {
        guard let report else {
            return nil
        }

        return "Power lock: \(report.state.ownsSleepDisable ? "on" : "off")"
    }

    var lastRequesterLine: String? {
        guard let requester = report?.state.lastRequester else {
            return nil
        }

        return "Last: \(requester.shortDisplayText(maxLength: 36))"
    }

    var canRunAwakeCommands: Bool {
        helperStatus == .enabled
    }

    var canInstallHelper: Bool {
        helperStatus == .notRegistered || helperStatus == .notFound
    }

    var canUnregisterHelper: Bool {
        helperStatus == .enabled || helperStatus == .requiresApproval
    }

    var helperNeedsApproval: Bool {
        helperStatus == .requiresApproval
    }

    func refresh() async {
        guard let controller else {
            errorMessage = setupError?.localizedDescription
            return
        }

        isRefreshing = true
        defer {
            isRefreshing = false
        }

        do {
            helperStatus = helper.registrationStatus
            report = try await readStatus(controller: controller)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startRefreshLoop() {
        guard refreshLoopTask == nil else {
            return
        }

        refreshLoopTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()

                do {
                    try await Task.sleep(for: .seconds(15))
                } catch {
                    break
                }
            }
        }
    }

    func keepAwake(minutes: Int) {
        Task {
            let requester = ActivationRequester(name: "dsmn", context: "menu")
            await mutate(local: {
                try $0.enableManual(minutes: minutes, requester: requester)
            }, helper: {
                try await self.helper.enableManual(minutes: minutes, requester: requester)
            })
        }
    }

    func stop() {
        Task {
            await mutate(local: {
                try $0.stop()
            }, helper: {
                try await self.helper.stop()
            })
        }
    }

    private func mutate(
        local localOperation: @escaping @Sendable (DSMNController) throws -> StatusReport,
        helper helperOperation: @escaping () async throws -> StatusReport
    ) async {
        guard let controller else {
            errorMessage = setupError?.localizedDescription
            return
        }

        isRefreshing = true
        defer {
            isRefreshing = false
        }

        do {
            helperStatus = helper.registrationStatus
            if helperStatus == .enabled {
                report = try await helperOperation()
            } else {
                report = try await Task.detached {
                    try localOperation(controller)
                }.value
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func installHelper() {
        Task {
            isRefreshing = true
            defer {
                isRefreshing = false
            }

            do {
                helperStatus = try helper.register()
                errorMessage = helperStatus == .requiresApproval ? "Approve helper in System Settings" : nil
            } catch {
                errorMessage = error.localizedDescription
                helperStatus = helper.registrationStatus
            }
        }
    }

    func unregisterHelper() {
        Task {
            isRefreshing = true
            defer {
                isRefreshing = false
            }

            do {
                helperStatus = try helper.unregister()
                errorMessage = nil
                await refresh()
            } catch {
                errorMessage = error.localizedDescription
                helperStatus = helper.registrationStatus
            }
        }
    }

    func openHelperSettings() {
        helper.openLoginItemsSettings()
    }

    private func readStatus(controller: DSMNController) async throws -> StatusReport {
        if helperStatus == .enabled {
            return try await helper.status()
        }

        return try await Task.detached {
            try controller.status()
        }.value
    }

    private func formatDuration(_ seconds: Int) -> String {
        let minutes = max(0, seconds / 60)
        if minutes < 60 {
            return "\(minutes)m"
        }

        let hours = minutes / 60
        let leftoverMinutes = minutes % 60
        return leftoverMinutes == 0 ? "\(hours)h" : "\(hours)h \(leftoverMinutes)m"
    }
}
