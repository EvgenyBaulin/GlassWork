import Foundation

/// Reads a URL. Tests replace this with canned responses, so no test reaches the network.
public protocol HTTPFetching: Sendable {
    func data(from url: URL) async throws -> Data
}

public enum HTTPError: Error, Equatable {
    case status(Int)
}

/// Keeps no cookies and no cache, so nothing about these requests stays on disk.
public struct URLSessionFetcher: HTTPFetching {
    private let session: URLSession

    public init(timeout: TimeInterval = 15) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }

    public func data(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        if let code = (response as? HTTPURLResponse)?.statusCode, !(200 ..< 300).contains(code) {
            throw HTTPError.status(code)
        }
        return data
    }
}

/// How the last attempt to reach a service went.
public enum FetchStatus: Sendable, Equatable {
    case idle, loading, ready, offline, failed

    /// Whether an error means there is no connection, rather than a service answering badly.
    static func isOffline(_ error: any Error) -> Bool {
        guard let code = (error as? URLError)?.code else { return false }
        let offline: [URLError.Code] = [
            .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
            .internationalRoamingOff, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .timedOut,
        ]
        return offline.contains(code)
    }
}

/// Decides when a service is asked again: every 30 minutes, or after 5 when the last attempt failed.
public struct RefreshSchedule: Sendable, Equatable {
    public static let interval: TimeInterval = 30 * 60
    public static let retryInterval: TimeInterval = 5 * 60

    private var lastAttempt: Date?
    private var lastFailed = false

    public init(lastSuccess: Date? = nil) {
        lastAttempt = lastSuccess
    }

    public func isDue(at date: Date) -> Bool {
        guard let lastAttempt else { return true }
        return date.timeIntervalSince(lastAttempt) >= (lastFailed ? Self.retryInterval : Self.interval)
    }

    public mutating func record(success: Bool, at date: Date) {
        lastAttempt = date
        lastFailed = !success
    }

    /// The next tick asks right away, for example after a city was added.
    public mutating func expire() {
        lastAttempt = nil
        lastFailed = false
    }
}
