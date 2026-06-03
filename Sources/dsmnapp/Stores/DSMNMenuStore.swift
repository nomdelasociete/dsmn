import DSMNCore
import Foundation

enum AgentHooksSetupStatus: Equatable, Sendable {
    case checking
    case installing
    case ready(String)
    case partial(Int, Int)
    case failed(String)

    var displayName: String {
        switch self {
        case .checking:
            "Checking hooks"
        case .installing:
            "Installing hooks"
        case let .ready(message):
            message
        case let .partial(installedCount, total):
            "\(installedCount)/\(total) hook targets installed"
        case let .failed(message):
            message
        }
    }

    var isReady: Bool {
        if case .ready = self {
            return true
        }

        return false
    }

    var isBusy: Bool {
        self == .checking || self == .installing
    }
}

@MainActor
final class DSMNMenuStore: ObservableObject {
    @Published private(set) var report: StatusReport?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var helperStatus: HelperRegistrationStatus = .notFound
    @Published private(set) var launchAtLoginStatus: LaunchAtLoginStatus = .notRegistered
    @Published private(set) var hookSetupStatus: AgentHooksSetupStatus = .checking

    private let controller: DSMNController?
    private let helper = HelperServiceClient()
    private let launchAtLogin = LaunchAtLoginService()
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

    var launchAtLoginStatusLine: String {
        "Launch at login: \(launchAtLoginStatus.displayName)"
    }

    var launchAtLoginEnabled: Bool {
        launchAtLoginStatus.isEnabled
    }

    var loginItemNeedsApproval: Bool {
        launchAtLoginStatus == .requiresApproval
    }

    var helperIsReady: Bool {
        helperStatus == .enabled
    }

    var hooksAreReady: Bool {
        hookSetupStatus.isReady
    }

    var hooksAreBusy: Bool {
        hookSetupStatus.isBusy
    }

    var hooksSummary: String {
        hookSetupStatus.displayName
    }

    var hooksActionTitle: String {
        switch hookSetupStatus {
        case .checking:
            "Checking..."
        case .installing:
            "Installing..."
        case .ready:
            "Reinstall"
        case .partial, .failed:
            "Install Hooks"
        }
    }

    var hooksStatusIconName: String {
        if hookSetupStatus.isReady {
            return "checkmark.circle.fill"
        }

        if case .failed = hookSetupStatus {
            return "exclamationmark.triangle.fill"
        }

        return "terminal"
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

    var triggerActivitySummary: TriggerActivitySummary {
        TriggerActivitySummary(requesters: report?.state.triggerHistory ?? [], bucketCount: 12)
    }

    var triggerActivityLine: String {
        triggerActivitySummary.menuLine
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

    var isProtectingSleep: Bool {
        guard let report else {
            return false
        }

        return report.decision.shouldPreventSleep || report.state.ownsSleepDisable
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
            launchAtLoginStatus = launchAtLogin.status
            if hookSetupStatus != .installing {
                hookSetupStatus = await inspectHookSetupStatus()
            }
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
            await stopNow()
        }
    }

    func stopNow() async {
        await mutate(local: {
            try $0.stop()
        }, helper: {
            try await self.helper.stop()
        })
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

    func setLaunchAtLogin(_ isEnabled: Bool) {
        Task {
            isRefreshing = true
            defer {
                isRefreshing = false
            }

            do {
                launchAtLoginStatus = try launchAtLogin.setEnabled(isEnabled)
                errorMessage = launchAtLoginStatus == .requiresApproval ? "Approve dsmn in Login Items" : nil
            } catch {
                errorMessage = error.localizedDescription
                launchAtLoginStatus = launchAtLogin.status
            }
        }
    }

    func openLoginItemsSettings() {
        launchAtLogin.openSettings()
    }

    func installAgentHooks() {
        Task {
            isRefreshing = true
            hookSetupStatus = .installing
            defer {
                isRefreshing = false
            }

            do {
                let dsmnctlPath = bundledDsmnctlPath()
                let reports = try await Task.detached {
                    try AgentHookInstaller(dsmnctlPath: dsmnctlPath).install()
                }.value
                let changedCount = reports.filter(\.changed).count
                let inspectedStatus = await inspectHookSetupStatus()
                if inspectedStatus.isReady {
                    hookSetupStatus = changedCount == 0
                        ? .ready("Hooks already installed")
                        : .ready("Hooks installed for Claude, Codex, Grok, and Pi")
                } else {
                    hookSetupStatus = inspectedStatus
                }
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
                hookSetupStatus = .failed("Hook install failed")
            }
        }
    }

    private func readStatus(controller: DSMNController) async throws -> StatusReport {
        if helperStatus == .enabled {
            return try await helper.status()
        }

        do {
            let helperReport = try await helper.status()
            helperStatus = .enabled
            return helperReport
        } catch {
            // SMAppService can report an ambiguous status when a different copy
            // of dsmn registered the helper. If XPC is unavailable too, fall
            // back to local status so the menu still opens.
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

    private func bundledDsmnctlPath() -> String? {
        let bundledPath = Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent("dsmnctl")
            .path

        if FileManager.default.isExecutableFile(atPath: bundledPath) {
            return bundledPath
        }

        return CommandLine.arguments.first
    }

    private func inspectHookSetupStatus() async -> AgentHooksSetupStatus {
        let home = FileManager.default.homeDirectoryForCurrentUser

        return await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            let hookScriptPath = home
                .appendingPathComponent(".dsmn", isDirectory: true)
                .appendingPathComponent("dsmn-agent-hook.sh")

            guard fileManager.isExecutableFile(atPath: hookScriptPath.path) else {
                return .partial(0, 4)
            }

            let targets: [(path: URL, markers: [String])] = [
                (
                    home.appendingPathComponent(".claude/settings.json"),
                    ["DSMN_HOOK_AGENT='claude'", "dsmn-agent-hook.sh"]
                ),
                (
                    home.appendingPathComponent(".codex/hooks.json"),
                    ["DSMN_HOOK_AGENT='codex'", "dsmn-agent-hook.sh"]
                ),
                (
                    home
                        .appendingPathComponent(".grok", isDirectory: true)
                        .appendingPathComponent("hooks", isDirectory: true)
                        .appendingPathComponent("dsmn.json"),
                    ["DSMN_HOOK_AGENT='grok'", "dsmn-agent-hook.sh"]
                ),
                (
                    home
                        .appendingPathComponent(".pi", isDirectory: true)
                        .appendingPathComponent("agent", isDirectory: true)
                        .appendingPathComponent("extensions", isDirectory: true)
                        .appendingPathComponent("dsmn.ts"),
                    ["DSMN_HOOK_AGENT: \"pi\"", "dsmn-agent-hook.sh"]
                )
            ]

            let installedCount = targets.filter { target in
                guard let contents = try? String(contentsOf: target.path, encoding: .utf8) else {
                    return false
                }

                return target.markers.allSatisfy { contents.contains($0) }
            }.count

            if installedCount == targets.count {
                return .ready("Claude, Codex, Grok, and Pi ready")
            }

            return .partial(installedCount, targets.count)
        }.value
    }
}
