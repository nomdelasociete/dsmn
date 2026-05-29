import Foundation

public enum DSMNError: Error, LocalizedError, Equatable {
    case processListingFailed(String)
    case invalidDuration(String)
    case invalidCommand(String)
    case stateDirectoryUnavailable

    public var errorDescription: String? {
        switch self {
        case .processListingFailed(let message):
            "Unable to list processes: \(message)"
        case .invalidDuration(let message):
            "Invalid duration: \(message)"
        case .invalidCommand(let message):
            "Invalid command: \(message)"
        case .stateDirectoryUnavailable:
            "Unable to resolve dsmn state directory"
        }
    }
}

public struct StateStore: Sendable {
    public var directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public var stateURL: URL {
        directory.appendingPathComponent("state.json")
    }

    public func load() throws -> DSMNState {
        guard FileManager.default.fileExists(atPath: stateURL.path) else {
            return DSMNState()
        }

        let data = try Data(contentsOf: stateURL)
        return try decoder.decode(DSMNState.self, from: data)
    }

    public func save(_ state: DSMNState) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(state)
        try data.write(to: stateURL, options: [.atomic])
    }

    public static func defaultStore(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> StateStore {
        if let override = environment["DSMN_STATE_DIR"], !override.isEmpty {
            return StateStore(directory: URL(fileURLWithPath: override, isDirectory: true))
        }

        if let home = environment["HOME"], !home.isEmpty {
            return StateStore(directory: URL(fileURLWithPath: home, isDirectory: true).appendingPathComponent(".dsmn"))
        }

        throw DSMNError.stateDirectoryUnavailable
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

