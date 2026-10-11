import DSMNCore
import Foundation

@MainActor
final class DSMNMenuStore: ObservableObject {
    let quitCoordinator = AppQuitCoordinator()
    @Published private(set) var report: StatusReport?
    @Published private(set) var errorMessage: String?
    @Published private(set) var manualTimerWarning: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isChangingTimer = false
    @Published private(set) var helperStatus: HelperRegistrationStatus = .notFound
    @Published private(set) var helperRuntimeInfo: HelperRuntimeInfo?
    @Published private(set) var helperXPCUnavailable = false
    @Published private(set) var launchAtLoginStatus: LaunchAtLoginStatus = .notRegistered
    @Published private(set) var hookSetupStatus: AgentHooksSetupStatus = .checking
    @Published private(set) var hookActionResultRows: [AgentHookActionResultRow] = []
    @Published private(set) var hookFallbackStatus = AgentHookFallbackStatus(
        isActive: false,
        logPath: AgentHookLogInspector.defaultLogPath,
        lastStartedAt: nil,
        fallbackSeconds: AgentHookLogInspector.defaultFallbackSeconds
    )
    @Published private(set) var helperUpdateRetryMessage: String?

    private let controller: DSMNController?
    private let helper = HelperServiceClient()
    private let launchAtLogin = LaunchAtLoginService()
    private let setupError: Error?
    private let stopHelperOverride: (() async throws -> StatusReport)?
    private var stopFailureMessage: String?
    private var refreshLoopTask: Task<Void, Never>?
    private var helperXPCUnavailableSince: Date?
    private let helperRepairAttentionDelay: TimeInterval = 45

    init() {
        stopHelperOverride = nil
        OnboardingPreferences.migrateLegacyKeysIfNeeded()

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

    /// Isolated Stop tests bypass preferences and all platform service queries.
    init(
        controller: DSMNController,
        helperStatus: HelperRegistrationStatus,
        initialReport: StatusReport? = nil,
        stopHelper: @escaping () async throws -> StatusReport
    ) {
        self.controller = controller
        self.helperStatus = helperStatus
        report = initialReport
        setupError = nil
        stopHelperOverride = stopHelper
    }

    var hasUnconfirmedStop: Bool {
        stopFailureMessage != nil
    }

    var onboardingWizardDismissed: Bool {
        OnboardingPreferences.wizardDismissed
    }

    var setupRemindersSuppressed: Bool {
        OnboardingPreferences.setupRemindersSuppressed
    }

    var setupIsComplete: Bool {
        setupMenuSignals.isSetupComplete
    }

    var menuBarIconState: MenuBarIconState {
        if manualTimerWarning != nil { return .warning }
        return MenuBarIconState.resolve(
            report: report,
            errorMessage: errorMessage,
            hookFallbackActive: hookFallbackNeedsAttention,
            setupNeedsAttention: menuBarShowsSetupAttention
        )
    }

    func menuBarProtectionIsActive(at date: Date) -> Bool {
        menuBarIconState == .manualActive
            && helperStatus == .enabled
            && !helperXPCUnavailable
            && report?.state.ownsSleepDisable == true
            && report?.decision.shouldPreventSleep == true
            && report?.state.manualIsActive(at: date) == true
    }

    var menuBarShowsSetupAttention: Bool {
        onboardingWizardDismissed
            && !setupRemindersSuppressed
            && setupMenuSignals.isSetupIncomplete
    }

    var menuSetupIncompleteStatusTitle: String? {
        SetupMenuPresentation.setupIncompleteStatusTitle(
            from: setupMenuSignals,
            wizardDismissed: onboardingWizardDismissed
        )
    }

    var prefersExpandedSetup: Bool {
        SetupMenuPresentation.prefersExpandedSetup(from: setupMenuSignals)
    }

    var canSuppressSetupReminders: Bool {
        onboardingWizardDismissed
            && !setupRemindersSuppressed
            && !setupIsComplete
    }

    var setupMenuSignals: SetupMenuSignals {
        var partialInstalled: Int?
        var partialTotal: Int?
        var hooksFailed = false
        var hooksNeedInstall = false
        var hooksNeedUpdate = false

        switch hookSetupStatus {
        case let .partial(installed, total):
            partialInstalled = installed
            partialTotal = total
            hooksNeedInstall = true
        case .outdated:
            hooksNeedUpdate = true
        case .failed:
            hooksFailed = true
            hooksNeedInstall = true
        case .checking, .installing:
            hooksNeedInstall = !hooksAreReady
        case .ready:
            break
        }

        let powerLockPending: Bool = {
            guard helperStatus == .enabled,
                  let report,
                  report.decision.shouldPreventSleep,
                  !report.state.ownsSleepDisable
            else {
                return false
            }

            return true
        }()

        return SetupMenuSignals(
            helperIsReady: helperIsReady,
            helperNeedsRepair: helperNeedsRepair,
            helperNeedsUpdate: helperNeedsUpdate,
            helperNeedsApproval: helperNeedsApproval,
            helperNeedsInstall: canInstallHelper,
            hooksAreReady: hooksAreReady,
            hooksPartialInstalled: partialInstalled,
            hooksPartialTotal: partialTotal,
            hooksFailed: hooksFailed,
            hooksNeedInstall: hooksNeedInstall,
            hooksNeedUpdate: hooksNeedUpdate,
            remindersSuppressed: setupRemindersSuppressed,
            powerLockPending: powerLockPending
        )
    }

    func suppressSetupReminders() {
        OnboardingPreferences.setupRemindersSuppressed = true
        objectWillChange.send()
    }

    var statusLine: String {
        guard let report else {
            return errorMessage ?? "Loading"
        }

        if hookFallbackNeedsAttention {
            if let remaining = report.state.manualRemainingSeconds(at: Date()), remaining > 0 {
                return "Active (hook fallback) - \(formatDuration(remaining))"
            }

            if report.decision.shouldPreventSleep {
                return "Active (hook fallback)"
            }

            return "Hook fallback"
        }

        if report.decision.shouldPreventSleep && !report.state.ownsSleepDisable {
            return helperStatus == .enabled ? "Applying" : "Helper required"
        }

        if let remaining = report.state.manualRemainingSeconds(at: Date()), remaining > 0 {
            return "Active - \(formatDuration(remaining))"
        }

        if report.decision.shouldPreventSleep {
            return "Active"
        }

        return "Off"
    }

    var helperStatusLine: String {
        if helperNeedsRepair {
            return "Helper: repair required"
        }

        if helperNeedsUpdate {
            return "Helper: update available"
        }

        return "Helper: \(helperStatus.displayName)"
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
        helperStatus == .enabled && !helperNeedsRepair
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
        AgentHookSetupPresentation.actionTitle(for: hookSetupStatus)
    }

    var hooksStatusIconName: String {
        if hookSetupStatus.isReady {
            return "checkmark.circle.fill"
        }

        if hookSetupStatus.needsUpdate {
            return "arrow.triangle.2.circlepath"
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
        SetupMenuPresentation.setupLine(from: setupMenuSignals)
    }

    var setupLineSystemImage: String {
        helperNeedsUpdate ? "arrow.triangle.2.circlepath" : "exclamationmark.circle"
    }

    var powerLockLine: String? {
        guard let report else {
            return nil
        }

        if hookFallbackNeedsAttention {
            return "Power lock: off (hook fallback caffeinate)"
        }

        return "Power lock: \(report.state.ownsSleepDisable ? "on" : "off")"
    }

    var hookFallbackLine: String? {
        guard hookFallbackNeedsAttention else {
            return nil
        }

        return "Hook fallback: caffeinate (no closed-lid lock)"
    }

    var lastRequesterLine: String? {
        guard let requester = report?.state.lastRequester else {
            return nil
        }

        return "Last: \(requester.shortDisplayText(maxLength: 36))"
    }

    var triggerActivitySummary: TriggerActivitySummary {
        TriggerActivitySummary(activityBuckets: report?.state.triggerActivityBuckets ?? [], bucketCount: 12)
    }

    var triggerActivityLine: String {
        return triggerActivitySummary.menuLine
    }

    var canRunAwakeCommands: Bool {
        helperStatus == .enabled
    }

    var canRunDoctor: Bool {
        controller != nil
    }

    var canRunHelperRepair: Bool {
        helperStatus == .enabled
    }

    var repairUnavailableExplanation: String? {
        guard !canRunHelperRepair else {
            return nil
        }

        switch helperStatus {
        case .notRegistered, .notFound:
            return "Install the helper to repair power lock and helper state."
        case .requiresApproval:
            return "Approve the helper in Login Items before running repair."
        case .enabled:
            return nil
        }
    }

    private var hookFallbackNeedsAttention: Bool {
        guard hookFallbackStatus.isActive else {
            return false
        }

        return report?.state.ownsSleepDisable != true
    }

    var helperNeedsUpdate: Bool {
        guard helperStatus == .enabled,
              let currentBuildNumber,
              let helperBuild = helperRuntimeInfo?.parentBundleVersion
        else {
            return false
        }

        return helperBuild < currentBuildNumber
    }

    var helperUpdateWasDeferred: Bool {
        guard let currentBuildNumber else {
            return false
        }

        return OnboardingPreferences.deferredHelperUpdateBuild == currentBuildNumber
    }

    var shouldPresentHelperUpdateReminder: Bool {
        onboardingWizardDismissed
            && helperNeedsUpdate
            && !helperUpdateWasDeferred
            && !helperNeedsRepair
    }

    var shouldPresentSetupAttentionReminder: Bool {
        onboardingWizardDismissed
            && !setupRemindersSuppressed
            && setupMenuSignals.isSetupIncomplete
            && !hookSetupStatus.isBusy
    }

    var setupAttentionReminderSignature: String? {
        guard shouldPresentSetupAttentionReminder else {
            return nil
        }

        return [
            helperStatusDisplayName,
            setupLine ?? "setup-incomplete",
            hooksSummary,
            errorMessage ?? "no-error"
        ].joined(separator: "|")
    }

    var helperUpdateDetail: String {
        let buildDetail: String

        if let helperBuild = helperRuntimeInfo?.parentBundleVersion,
           let currentBuildNumber {
            buildDetail = " The helper is on build \(helperBuild); the app is build \(currentBuildNumber)."
        } else {
            buildDetail = ""
        }

        return "dsmn was updated and the helper is still running the previous build.\(buildDetail) Existing timers can keep running; update the helper when convenient so the privileged code matches the app."
    }

    var helperUpdateActionTitle: String {
        helperUpdateRetryMessage == nil ? "Update Helper" : "Try Again"
    }

    var helperNeedsRepair: Bool {
        helperStatus == .enabled
            && helperXPCUnavailableIsPersistent
            && !helperXPCUnavailableLooksTransient
    }

    var helperStatusDisplayName: String {
        if helperNeedsRepair {
            return "repair required"
        }

        if helperXPCUnavailableLooksTransient {
            return "retrying"
        }

        return helperStatus.displayName
    }

    var canInstallHelper: Bool {
        helperStatus == .notRegistered || helperStatus == .notFound
    }

    var canUpdateHelper: Bool {
        helperNeedsUpdate || helperNeedsRepair
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

    private var currentBuildNumber: Int? {
        if let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
            return Int(value)
        }

        if let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? Int {
            return value
        }

        return nil
    }

    func refresh() async {
        defer {
            if let stopFailureMessage {
                errorMessage = stopFailureMessage
            }
        }
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
            helperRuntimeInfo = await helper.runtimeInfo()
            launchAtLoginStatus = launchAtLogin.status
            if !hookSetupStatus.isInstalling {
                hookSetupStatus = await inspectHookSetupStatus()
            }
            hookFallbackStatus = AgentHookLogInspector.recentFallbackStatus()
            report = try await readStatus(controller: controller)
            await retryHelperXPCConnectionIfNeeded()
            await recoverActiveHookFallbackAfterSetupIfNeeded(reason: "setup_ready")
            clearHelperUpdateRetryIfResolved()
            errorMessage = helperUnavailableMessage
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

    func keepAwake(minutes: Int, action: ManualTimerAction = .replace) {
        Task {
            try? await setManualTimer(minutes: minutes, action: action)
        }
    }

    func setManualTimer(minutes: Int, action: ManualTimerAction) async throws {
        guard !isChangingTimer else {
            throw DSMNHelperClientError.commandFailed("A timer request is already in progress.")
        }
        isChangingTimer = true
        defer { isChangingTimer = false }
        do {
            let confirmed = try await ManualTimerRequest.run(minutes: minutes, action: action, replace: {
                try await self.helper.enableManual(minutes: $0, requester: ActivationRequester(name: "dsmn", context: "menu"))
            }, add: {
                try await self.helper.addManualTime(minutes: $0)
            })
            report = confirmed
            stopFailureMessage = nil
            markHelperXPCAvailable()
            errorMessage = nil
            recordManualTimerWarning(report: confirmed, action: action)
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func recordManualTimerWarning(report: StatusReport, action: ManualTimerAction) {
        // Refresh and unrelated operations must not erase an unacknowledged Add.
        if let warning = ManualTimerRequest.appliedWarning(for: report, action: action) {
            manualTimerWarning = warning
        } else if report.state.ownsSleepDisable, report.decision.shouldPreventSleep,
                  report.state.manualIsActive(at: report.generatedAt) {
            manualTimerWarning = nil
        }
    }

    func dismissManualTimerWarning() {
        manualTimerWarning = nil
    }

    func stop() {
        Task {
            _ = await stopNow()
        }
    }

    func stopNow() async -> StopOutcome {
        isRefreshing = true
        defer { isRefreshing = false }

        // XPC is authoritative even when another app copy makes registration ambiguous.
        let outcome = await StopRequest.run(helper: {
            if let stopHelperOverride = self.stopHelperOverride {
                return try await stopHelperOverride()
            }
            return try await self.helper.stop()
        }, local: {
            guard let controller = self.controller else {
                throw self.setupError ?? DSMNError.stateDirectoryUnavailable
            }
            return try await Task.detached { try controller.stop() }.value
        })

        if let updatedReport = outcome.report {
            report = updatedReport
        }
        switch outcome {
        case .helperConfirmed, .unconfirmed(.some, _):
            helperStatus = .enabled
            markHelperXPCAvailable()
        case .localOnly:
            markHelperXPCUnavailable()
        case .unconfirmed(.none, _):
            break
        }
        stopFailureMessage = outcome.failureMessage
        errorMessage = outcome.failureMessage
        if outcome.isHelperConfirmed { manualTimerWarning = nil }
        return outcome
    }

    func installHelper() {
        Task {
            isRefreshing = true
            defer {
                isRefreshing = false
            }

            do {
                helperStatus = try helper.register()
                helperRuntimeInfo = await helper.runtimeInfo()
                OnboardingPreferences.deferredHelperUpdateBuild = nil
                helperUpdateRetryMessage = nil
                errorMessage = helperStatus == .requiresApproval ? "Approve helper in System Settings" : nil
                if helperStatus == .enabled {
                    await refresh()
                }
            } catch {
                errorMessage = error.localizedDescription
                helperStatus = helper.registrationStatus
            }
        }
    }

    func updateHelper() {
        Task {
            isRefreshing = true
            defer {
                isRefreshing = false
            }

            do {
                helperStatus = try helper.updateRegistration()
                helperRuntimeInfo = await helper.runtimeInfo()
                OnboardingPreferences.deferredHelperUpdateBuild = nil
                helperUpdateRetryMessage = nil
                markHelperXPCAvailable()
                errorMessage = helperStatus == .requiresApproval ? "Approve helper in System Settings" : nil
                await refresh()
                await recoverActiveHookFallbackAfterSetupIfNeeded(reason: "helper_update")
            } catch {
                helperStatus = helper.registrationStatus
                helperRuntimeInfo = await helper.runtimeInfo()

                if shouldOfferHelperUpdateRetry(for: error) {
                    helperUpdateRetryMessage = "macOS may need a second confirmation after refreshing the helper registration. Click Try Again to finish."
                    errorMessage = nil
                } else {
                    helperUpdateRetryMessage = nil
                    errorMessage = error.localizedDescription
                }
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
                helperRuntimeInfo = await helper.runtimeInfo()
                OnboardingPreferences.deferredHelperUpdateBuild = nil
                helperUpdateRetryMessage = nil
                markHelperXPCAvailable()
                errorMessage = nil
                await refresh()
            } catch {
                errorMessage = error.localizedDescription
                helperStatus = helper.registrationStatus
                helperRuntimeInfo = await helper.runtimeInfo()
            }
        }
    }

    func openHelperSettings() {
        helper.openLoginItemsSettings()
    }

    func deferHelperUpdateReminder() {
        guard let currentBuildNumber else {
            return
        }

        OnboardingPreferences.deferredHelperUpdateBuild = currentBuildNumber
        helperUpdateRetryMessage = nil
        objectWillChange.send()
    }

    private func shouldOfferHelperUpdateRetry(for error: Error) -> Bool {
        guard helperStatus == .enabled, helperNeedsUpdate else {
            return false
        }

        let description = [
            error.localizedDescription,
            String(reflecting: error)
        ].joined(separator: " ").localizedLowercase

        return description.contains("not permitted")
            || description.contains("notpermitted")
            || description.contains("not authorized")
            || description.contains("permission")
            || description.contains("not allowed")
    }

    private func clearHelperUpdateRetryIfResolved() {
        if !helperNeedsUpdate || helperNeedsRepair || helperNeedsApproval {
            helperUpdateRetryMessage = nil
        }
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

    func runDoctor() {
        Task {
            isRefreshing = true
            defer {
                isRefreshing = false
            }

            do {
                let report = try await doctorReportText()
                DoctorWindowPresenter.show(report: report)
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func runRepair() {
        guard canRunHelperRepair else {
            if let repairUnavailableExplanation {
                RepairResultPresenter.show(
                    result: "",
                    error: repairUnavailableExplanation
                )
            }
            return
        }

        Task {
            isRefreshing = true
            defer {
                isRefreshing = false
            }

            do {
                let report = try await helper.repair()
                markHelperXPCAvailable()
                self.report = report
                let result = DoctorReportFormatter.formatRepairResult(report, source: .helper)
                RepairResultPresenter.show(result: result)
                AgentHookLogInspector.markFallbackResolved(reason: "repair")
                hookFallbackStatus = AgentHookLogInspector.recentFallbackStatus()
                errorMessage = nil
                await refresh()
            } catch {
                if helperStatus == .enabled {
                    markHelperXPCUnavailable()
                } else {
                    markHelperXPCAvailable()
                }
                RepairResultPresenter.show(result: "", error: error.localizedDescription)
                errorMessage = error.localizedDescription
            }
        }
    }

    private func doctorReportText() async throws -> String {
        guard let controller else {
            if let setupError {
                throw setupError
            }

            throw DSMNError.stateDirectoryUnavailable
        }

        let liveSleepDisabled = try? await Task.detached(priority: .utility) {
            try SleepDiagnosticsInspector().report().sleepDisabled
        }.value
        let hookFallback = AgentHookLogInspector.recentFallbackStatus()
        let dsmnctlPath = bundledDsmnctlPath()
        let hookInspection = try? await Task.detached(priority: .utility) {
            try AgentHookInstaller(dsmnctlPath: dsmnctlPath).inspect()
        }.value
        hookFallbackStatus = hookFallback

        if helperStatus == .enabled {
            do {
                let report = try await helper.status()
                markHelperXPCAvailable()
                return DoctorReportFormatter.format(
                    report: report,
                    source: .helper,
                    liveSleepDisabled: liveSleepDisabled,
                    hookFallback: hookFallback,
                    hookInspection: hookInspection
                )
            } catch {
                markHelperXPCUnavailable()
                let report = try await Task.detached {
                    try controller.status()
                }.value
                return DoctorReportFormatter.format(
                    report: report,
                    source: .local,
                    liveSleepDisabled: liveSleepDisabled,
                    hookFallback: hookFallback,
                    hookInspection: hookInspection
                )
            }
        }

        let report = try await Task.detached {
            try controller.status()
        }.value

        return DoctorReportFormatter.format(
            report: report,
            source: .local,
            liveSleepDisabled: liveSleepDisabled,
            hookFallback: hookFallback,
            hookInspection: hookInspection
        )
    }

    func installAgentHooks() {
        guard let action = AgentHookSetupPresentation.action(for: hookSetupStatus) else {
            return
        }

        Task {
            isRefreshing = true
            hookSetupStatus = AgentHookSetupPresentation.startedStatus(for: action)
            hookActionResultRows = []
            defer {
                isRefreshing = false
            }

            let dsmnctlPath = bundledDsmnctlPath()
            let reports = await Task.detached(priority: .utility) {
                AgentHookInstaller(dsmnctlPath: dsmnctlPath).installReportingFailures()
            }.value
            let resultRows = AgentHookSetupPresentation.resultRows(for: action, reports: reports)
            hookActionResultRows = resultRows

            if resultRows.contains(where: { $0.state == .failed }) {
                hookSetupStatus = AgentHookSetupPresentation.completedStatus(for: action, reports: reports)
                errorMessage = nil
                return
            }

            let inspectedStatus = await inspectHookSetupStatus()
            if inspectedStatus.isReady {
                hookSetupStatus = AgentHookSetupPresentation.completedStatus(for: action, reports: reports)
            } else {
                hookSetupStatus = inspectedStatus
            }
            await recoverActiveHookFallbackAfterSetupIfNeeded(reason: "hooks_ready")
            errorMessage = nil
        }
    }

    func uninstallAgentHooks() {
        Task {
            isRefreshing = true
            defer {
                isRefreshing = false
            }

            do {
                let reports = try await Task.detached {
                    try AgentHookInstaller().uninstall()
                }.value
                let removedCount = reports.filter(\.changed).count
                hookSetupStatus = await inspectHookSetupStatus()
                if removedCount == 0 {
                    errorMessage = nil
                    HookUninstallResultPresenter.show(
                        title: "Hooks Already Removed",
                        detail: "No dsmn hook entries were found for \(AgentHookTarget.joinedDisplayNames(short: true, conjunction: "or"))."
                    )
                } else {
                    errorMessage = nil
                    let lines = reports
                        .filter(\.changed)
                        .map { "\($0.target): \($0.message)" }
                        .joined(separator: "\n")
                    HookUninstallResultPresenter.show(
                        title: "Agent Hooks Removed",
                        detail: lines
                    )
                }
            } catch {
                errorMessage = error.localizedDescription
                HookUninstallResultPresenter.show(
                    title: "Hook Removal Failed",
                    detail: error.localizedDescription,
                    isError: true
                )
            }
        }
    }

    private func readStatus(controller: DSMNController) async throws -> StatusReport {
        do {
            let helperReport = try await helper.status()
            helperStatus = .enabled
            markHelperXPCAvailable()
            return helperReport
        } catch {
            // SMAppService can report an ambiguous status when a different copy
            // of dsmn registered the helper. If XPC is unavailable too, fall
            // back to local status so the menu still opens.
            if helperStatus == .enabled {
                markHelperXPCUnavailable()
            } else {
                markHelperXPCAvailable()
            }
        }

        return try await Task.detached {
            try controller.status()
        }.value
    }

    private func retryHelperXPCConnectionIfNeeded() async {
        guard helperStatus == .enabled, helperXPCUnavailable else {
            return
        }

        do {
            try await Task.sleep(for: .milliseconds(750))
        } catch {
            return
        }

        do {
            report = try await helper.status()
            markHelperXPCAvailable()
            await recoverActiveHookFallbackAfterSetupIfNeeded(reason: "helper_xpc_recovered")
        } catch {
            markHelperXPCUnavailable()
        }
    }

    private var helperXPCUnavailableIsPersistent: Bool {
        guard helperXPCUnavailable, let helperXPCUnavailableSince else {
            return false
        }

        return Date().timeIntervalSince(helperXPCUnavailableSince) >= helperRepairAttentionDelay
    }

    private var helperXPCUnavailableLooksTransient: Bool {
        helperStatus == .enabled
            && helperXPCUnavailable
            && helperRuntimeInfo?.isRunning == true
    }

    private var helperUnavailableMessage: String? {
        if helperNeedsRepair {
            return "Helper unavailable; repair helper"
        }

        if helperXPCUnavailableLooksTransient {
            return "Helper busy; retrying"
        }

        return nil
    }

    private func markHelperXPCAvailable() {
        helperXPCUnavailable = false
        helperXPCUnavailableSince = nil
    }

    private func markHelperXPCUnavailable() {
        helperXPCUnavailable = true
        helperXPCUnavailableSince = helperXPCUnavailableSince ?? Date()
    }

    private func recoverActiveHookFallbackAfterSetupIfNeeded(reason: String) async {
        guard hookFallbackNeedsAttention,
              setupMenuSignals.isSetupComplete,
              helperStatus == .enabled,
              !helperXPCUnavailable,
              let minutes = HookFallbackRecoveryPolicy.remainingMinutes(for: hookFallbackStatus)
        else {
            return
        }

        do {
            let requester = ActivationRequester(
                name: "dsmn",
                context: "recovered hook fallback",
                event: reason
            )
            report = try await helper.enableManual(minutes: minutes, requester: requester)
            markHelperXPCAvailable()
            AgentHookLogInspector.markFallbackResolved(reason: reason)
            hookFallbackStatus = AgentHookLogInspector.recentFallbackStatus()
        } catch {
            if helperStatus == .enabled {
                markHelperXPCUnavailable()
            } else {
                markHelperXPCAvailable()
            }
            errorMessage = error.localizedDescription
        }
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
        let dsmnctlPath = bundledDsmnctlPath()

        return await Task.detached(priority: .utility) {
            do {
                let inspection = try AgentHookInstaller(dsmnctlPath: dsmnctlPath).inspect()
                if inspection.isCurrent {
                    return .ready("\(AgentHookTarget.joinedDisplayNames(short: true)) ready")
                }

                if inspection.needsUpdate {
                    return .outdated("Hooks update available")
                }

                if inspection.hookScriptStatus == .missing || inspection.hookScriptStatus == .notExecutable {
                    return .partial(0, inspection.targetCount)
                }

                return .partial(inspection.installedTargetCount, inspection.targetCount)
            } catch {
                return .failed("Hook check failed")
            }
        }.value
    }
}
