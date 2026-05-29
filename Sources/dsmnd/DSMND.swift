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
        let delegate = DSMNHelperXPCDelegate()
        let listener = NSXPCListener(machServiceName: DSMNServiceConstants.helperMachServiceName)
        listener.delegate = delegate
        listener.resume()
        RunLoop.main.run()
    }
}
