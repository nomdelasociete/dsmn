import DSMNCore
import Foundation

@MainActor
final class DSMNMenuStore: ObservableObject {
    @Published private(set) var report: StatusReport?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRefreshing = false

    private let controller: DSMNController?
    private let setupError: Error?

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

    var menuBarSystemImage: String {
        return "figure.run"
    }

    var statusLine: String {
        guard let report else {
            return errorMessage ?? "Loading"
        }

        if report.decision.shouldPreventSleep {
            if let remaining = report.manualRemainingSeconds, remaining > 0 {
                return "Active - \(formatDuration(remaining))"
            }

            return "Active - auto"
        }

        if report.state.autoEnabled {
            return "Auto armed"
        }

        return "Off"
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
            report = try await Task.detached {
                try controller.status()
            }.value
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func keepAwake(minutes: Int) {
        Task {
            await mutate {
                try $0.enableManual(minutes: minutes)
            }
        }
    }

    func toggleAuto() {
        Task {
            await mutate {
                try $0.setAuto(.toggle)
            }
        }
    }

    func setAuto(_ enabled: Bool) {
        Task {
            await mutate {
                try $0.setAuto(enabled ? .on : .off)
            }
        }
    }

    func stop() {
        Task {
            await mutate {
                try $0.stop()
            }
        }
    }

    private func mutate(_ operation: @escaping @Sendable (DSMNController) throws -> StatusReport) async {
        guard let controller else {
            errorMessage = setupError?.localizedDescription
            return
        }

        isRefreshing = true
        defer {
            isRefreshing = false
        }

        do {
            report = try await Task.detached {
                try operation(controller)
            }.value
            errorMessage = nil
        } catch {
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
}
