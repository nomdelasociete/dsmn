import Foundation

enum FeedbackCategory: String, CaseIterable, Identifiable {
    case bug
    case idea
    case question
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bug:
            "Bug"
        case .idea:
            "Idea"
        case .question:
            "Question"
        case .other:
            "Other"
        }
    }
}

struct FeedbackSubmission: Encodable, Sendable {
    var category: String
    var message: String
    var email: String?
    var appVersion: String
    var buildNumber: String
    var osVersion: String
    var diagnostics: [String: String]
}

enum FeedbackServiceError: LocalizedError {
    case invalidEndpoint
    case invalidResponse
    case invalidFeedback
    case rateLimited
    case serverError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            "Feedback endpoint is not configured."
        case .invalidResponse:
            "dsmn.app returned an invalid response."
        case .invalidFeedback:
            "Check the message and optional email, then try again."
        case .rateLimited:
            "Too many feedback messages. Try again later."
        case let .serverError(statusCode):
            "dsmn.app returned HTTP \(statusCode)."
        }
    }
}

struct FeedbackService: Sendable {
    var endpoint: URL
    var session: URLSession = .shared

    init(endpoint: URL? = nil, session: URLSession = .shared) {
        self.endpoint = endpoint ?? Self.defaultEndpoint
        self.session = session
    }

    func submit(_ submission: FeedbackSubmission) async throws {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        request.httpBody = try JSONEncoder().encode(submission)

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FeedbackServiceError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200..<300:
            return
        case 422:
            throw FeedbackServiceError.invalidFeedback
        case 429:
            throw FeedbackServiceError.rateLimited
        default:
            throw FeedbackServiceError.serverError(httpResponse.statusCode)
        }
    }

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }

    static var osVersion: String {
        ProcessInfo.processInfo.operatingSystemVersionString
    }

    private static var defaultEndpoint: URL {
        if let value = ProcessInfo.processInfo.environment["DSMN_FEEDBACK_URL"],
           let url = URL(string: value),
           ["https", "http"].contains(url.scheme?.lowercased()) {
            return url
        }

        guard let url = URL(string: "https://dsmn.app/api/feedback") else {
            preconditionFailure("Invalid feedback endpoint")
        }

        return url
    }
}
