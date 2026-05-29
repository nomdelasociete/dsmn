import DSMNCore
import Foundation

final class DSMNHelperXPCService: NSObject, DSMNHelperXPCProtocol {
    private let controller: DSMNController
    private let powerManager: any PowerManaging
    private var reconcileTimer: Timer?

    init(
        controller: DSMNController = DSMNController(store: StateStore.daemonStore()),
        powerManager: any PowerManaging = PMSetPowerManager(dryRun: DSMNHelperXPCService.shouldDryRunPowerChanges())
    ) {
        self.controller = controller
        self.powerManager = powerManager
    }

    func status(withReply reply: @escaping (String) -> Void) {
        reply(encode {
            .success(status: try controller.status())
        })
    }

    func enableManual(minutes: Int, withReply reply: @escaping (String) -> Void) {
        reply(encode {
            _ = try controller.enableManual(minutes: minutes)
            return .success(run: try controller.reconcile(powerManager: powerManager))
        })
    }

    func setAuto(enabled: Bool, withReply reply: @escaping (String) -> Void) {
        reply(encode {
            _ = try controller.setAuto(enabled ? .on : .off)
            return .success(run: try controller.reconcile(powerManager: powerManager))
        })
    }

    func toggleAuto(withReply reply: @escaping (String) -> Void) {
        reply(encode {
            _ = try controller.setAuto(.toggle)
            return .success(run: try controller.reconcile(powerManager: powerManager))
        })
    }

    func stop(withReply reply: @escaping (String) -> Void) {
        reply(encode {
            _ = try controller.stop()
            return .success(run: try controller.reconcile(powerManager: powerManager))
        })
    }

    func reconcile(withReply reply: @escaping (String) -> Void) {
        reply(encode {
            .success(run: try controller.reconcile(powerManager: powerManager))
        })
    }

    func startPeriodicReconcile(interval: TimeInterval) {
        reconcileSilently()
        reconcileTimer = Timer.scheduledTimer(
            timeInterval: interval,
            target: self,
            selector: #selector(handlePeriodicReconcile),
            userInfo: nil,
            repeats: true
        )
    }

    @objc private func handlePeriodicReconcile(_ timer: Timer) {
        reconcileSilently()
    }

    private func reconcileSilently() {
        do {
            _ = try controller.reconcile(powerManager: powerManager)
        } catch {
            fputs("dsmnd: reconcile failed: \(error.localizedDescription)\n", stderr)
        }
    }

    private func encode(_ operation: () throws -> DSMNHelperCommandResponse) -> String {
        let response: DSMNHelperCommandResponse
        do {
            response = try operation()
        } catch {
            response = .failure(error)
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(response)
            return String(data: data, encoding: .utf8) ?? #"{"error":"encoding failed"}"#
        } catch {
            return #"{"error":"encoding failed"}"#
        }
    }

    private static func shouldDryRunPowerChanges() -> Bool {
        let environment = ProcessInfo.processInfo.environment

        if environment["DSMN_APPLY_PMSET"] == "1" {
            return false
        }

        if environment["DSMN_APPLY_PMSET"] == "0" {
            return true
        }

        return getuid() != 0
    }
}

final class DSMNHelperXPCDelegate: NSObject, NSXPCListenerDelegate {
    private let service: DSMNHelperXPCService

    init(service: DSMNHelperXPCService = DSMNHelperXPCService()) {
        self.service = service
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: DSMNHelperXPCProtocol.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }
}
