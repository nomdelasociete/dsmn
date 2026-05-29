import DSMNCore
import Darwin
import Foundation

@main
struct DSMND {
    static func main() {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            if arguments.first == "serve" {
                serve()
                return
            }

            let store = arguments.first == "daemon-once" ? StateStore.daemonStore() : try StateStore.defaultStore()
            let controller = DSMNController(store: store)
            let dryRun = ProcessInfo.processInfo.environment["DSMN_APPLY_PMSET"] != "1"
            let powerManager = PMSetPowerManager(dryRun: dryRun)
            let report = try controller.reconcile(powerManager: powerManager)

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(report)
            print(String(data: data, encoding: .utf8) ?? "{}")
            if dryRun {
                fputs("dsmnd: dry-run; set DSMN_APPLY_PMSET=1 to execute pmset\n", stderr)
            }
        } catch {
            fputs("dsmnd: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func serve() {
        let service = DSMNHelperXPCService()
        service.startPeriodicReconcile(interval: reconcileInterval())

        let delegate = DSMNHelperXPCDelegate(service: service)
        let listener = NSXPCListener(machServiceName: DSMNServiceConstants.helperMachServiceName)
        listener.delegate = delegate
        listener.resume()
        RunLoop.main.run()
    }

    private static func reconcileInterval() -> TimeInterval {
        let rawValue = ProcessInfo.processInfo.environment["DSMN_RECONCILE_INTERVAL_SECONDS"] ?? ""
        guard let interval = TimeInterval(rawValue), interval > 0 else {
            return 30
        }

        return interval
    }
}
