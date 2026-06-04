import Foundation

public enum DSMNServiceConstants {
    public static let appBundleIdentifier = "com.nomdelasociete.dsmn"
    public static let ctlBundleIdentifier = "com.nomdelasociete.dsmn.dsmnctl"
    public static let developmentTeamID = "JSFMAD28GS"
    public static let helperLabel = "com.nomdelasociete.dsmn.helper"
    public static let helperMachServiceName = "com.nomdelasociete.dsmn.helper"
    public static let helperPlistName = "com.nomdelasociete.dsmn.helper.plist"

    public static let trustedXPCClientBundleIdentifiers = [
        appBundleIdentifier,
        ctlBundleIdentifier
    ]
}

@objc(DSMNHelperXPCProtocol)
public protocol DSMNHelperXPCProtocol {
    func status(withReply reply: @escaping (String) -> Void)
    func enableManual(minutes: Int, withReply reply: @escaping (String) -> Void)
    func enableManualV2(
        minutes: Int,
        extendOnly: Bool,
        requesterName: String?,
        requesterContext: String?,
        requesterEvent: String?,
        withReply reply: @escaping (String) -> Void
    )
    func stop(withReply reply: @escaping (String) -> Void)
    func reconcile(withReply reply: @escaping (String) -> Void)
    func repair(withReply reply: @escaping (String) -> Void)
}

public struct DSMNHelperCommandResponse: Codable, Equatable, Sendable {
    public var status: StatusReport?
    public var run: DaemonRunReport?
    public var error: String?

    public init(status: StatusReport? = nil, run: DaemonRunReport? = nil, error: String? = nil) {
        self.status = status
        self.run = run
        self.error = error
    }

    public static func success(status: StatusReport) -> DSMNHelperCommandResponse {
        DSMNHelperCommandResponse(status: status)
    }

    public static func success(run: DaemonRunReport) -> DSMNHelperCommandResponse {
        DSMNHelperCommandResponse(status: run.status, run: run)
    }

    public static func failure(_ error: Error) -> DSMNHelperCommandResponse {
        DSMNHelperCommandResponse(error: error.localizedDescription)
    }
}

public enum DSMNHelperClientError: Error, LocalizedError {
    case unavailable(String)
    case invalidResponse(String)
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .unavailable(let message):
            "Helper unavailable: \(message)"
        case .invalidResponse(let message):
            "Invalid helper response: \(message)"
        case .timedOut:
            "Helper request timed out"
        }
    }
}

public final class DSMNHelperXPCClient: @unchecked Sendable {
    public var machServiceName: String
    public var timeout: TimeInterval

    public init(
        machServiceName: String = DSMNServiceConstants.helperMachServiceName,
        timeout: TimeInterval = 2
    ) {
        self.machServiceName = machServiceName
        self.timeout = timeout
    }

    public func status() throws -> StatusReport {
        try request { proxy, reply in
            proxy.status(withReply: reply)
        }
    }

    public func enableManual(
        minutes: Int,
        extendOnly: Bool = false,
        requester: ActivationRequester? = nil
    ) throws -> StatusReport {
        if extendOnly || requester != nil {
            do {
                return try request { proxy, reply in
                    proxy.enableManualV2(
                        minutes: minutes,
                        extendOnly: extendOnly,
                        requesterName: requester?.name,
                        requesterContext: requester?.context,
                        requesterEvent: requester?.event,
                        withReply: reply
                    )
                }
            } catch {
                if extendOnly {
                    return try extendManualWithLegacyHelper(minutes: minutes)
                }
            }
        }

        return try request { proxy, reply in
            proxy.enableManual(minutes: minutes, withReply: reply)
        }
    }

    public func stop() throws -> StatusReport {
        try request { proxy, reply in
            proxy.stop(withReply: reply)
        }
    }

    public func reconcile() throws -> DaemonRunReport {
        let response = try requestEnvelope { proxy, reply in
            proxy.reconcile(withReply: reply)
        }

        guard let run = response.run else {
            throw DSMNHelperClientError.invalidResponse("missing run report")
        }

        return run
    }

    public func repair() throws -> StatusReport {
        try request { proxy, reply in
            proxy.repair(withReply: reply)
        }
    }

    private func extendManualWithLegacyHelper(minutes: Int) throws -> StatusReport {
        let current = try status()
        let requestedUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))

        if let manualUntil = current.state.manualUntil, manualUntil > requestedUntil {
            return try reconcile().status
        }

        return try request { proxy, reply in
            proxy.enableManual(minutes: minutes, withReply: reply)
        }
    }

    private func request(
        _ send: (DSMNHelperXPCProtocol, @escaping (String) -> Void) -> Void
    ) throws -> StatusReport {
        let response = try requestEnvelope(send)

        guard let status = response.status else {
            throw DSMNHelperClientError.invalidResponse("missing status report")
        }

        return status
    }

    private func requestEnvelope(
        _ send: (DSMNHelperXPCProtocol, @escaping (String) -> Void) -> Void
    ) throws -> DSMNHelperCommandResponse {
        let connection = NSXPCConnection(machServiceName: machServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: DSMNHelperXPCProtocol.self)

        let completion = XPCRequestCompletion<DSMNHelperCommandResponse>()
        connection.invalidationHandler = {
            completion.complete(.failure(DSMNHelperClientError.unavailable("connection invalidated")))
        }
        connection.interruptionHandler = {
            completion.complete(.failure(DSMNHelperClientError.unavailable("connection interrupted")))
        }

        connection.resume()
        defer {
            connection.invalidate()
        }

        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
            completion.complete(.failure(error))
        }) as? DSMNHelperXPCProtocol else {
            throw DSMNHelperClientError.unavailable("unable to create XPC proxy")
        }

        send(proxy) { payload in
            completion.complete(Result {
                try Self.decodeResponse(payload)
            })
        }

        return try completion.wait(timeout: timeout)
    }

    private static func decodeResponse(_ payload: String) throws -> DSMNHelperCommandResponse {
        guard let data = payload.data(using: .utf8) else {
            throw DSMNHelperClientError.invalidResponse("non-UTF8 payload")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response = try decoder.decode(DSMNHelperCommandResponse.self, from: data)

        if let error = response.error {
            throw DSMNHelperClientError.unavailable(error)
        }

        return response
    }
}

private final class XPCRequestCompletion<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var result: Result<Value, Error>?

    func complete(_ result: Result<Value, Error>) {
        lock.lock()
        defer {
            lock.unlock()
        }

        guard self.result == nil else {
            return
        }

        self.result = result
        semaphore.signal()
    }

    func wait(timeout: TimeInterval) throws -> Value {
        let deadline = DispatchTime.now() + timeout
        if semaphore.wait(timeout: deadline) == .timedOut {
            throw DSMNHelperClientError.timedOut
        }

        lock.lock()
        defer {
            lock.unlock()
        }

        guard let result else {
            throw DSMNHelperClientError.invalidResponse("missing completion")
        }

        return try result.get()
    }
}
