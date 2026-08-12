//
//  MastodonHTTP.swift
//  Pachyderm
//
//  Created by Hariz Shirazi on 2025-06-12.
//

import Foundation
import os

// MARK: - Credentials

/// All the data that a request to one instance as one user needs.
nonisolated struct MastodonCredentials: Hashable, Sendable {
    /// Only the host. Example: `mastodon.social`. No scheme and no path.
    var host: String
    var accessToken: String?

    var isAuthenticated: Bool { !(accessToken ?? "").isEmpty }

    /// Makes a bare host from the text of the user.
    ///
    /// Users give text such as `https://mastodon.social/`, `@me@host`, and
    /// text with spaces at the end. Such text makes each subsequent URL
    /// incorrect.
    static func normalize(host input: String) -> String {
        var host = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in ["https://", "http://"] where host.hasPrefix(prefix) {
            host.removeFirst(prefix.count)
        }
        // `@user@host` and `user@host` give `host`.
        if let at = host.lastIndex(of: "@") {
            host = String(host[host.index(after: at)...])
        }
        if let slash = host.firstIndex(of: "/") {
            host = String(host[..<slash])
        }
        return host
    }

    /// A host is usable when it stays after the `normalize` function and
    /// makes a valid URL.
    static func isValid(host: String) -> Bool {
        let host = normalize(host: host)
        guard !host.isEmpty, !host.contains(" "), host.contains(".") else { return false }
        return URL(string: "https://\(host)") != nil
    }
}

// MARK: - Errors

nonisolated enum MastodonError: LocalizedError, Sendable {
    case invalidHost(String)
    case notAuthenticated
    /// A status code that is not in the 2xx group. The `message` value is the
    /// explanation of the server, when the server sends one.
    case server(status: Int, message: String?)
    case rateLimited(retryAfter: TimeInterval?)
    case decoding(type: String, underlying: String)
    case transport(String)
    /// The software of the instance does not have the requested feature.
    case unsupported(feature: String, software: String?)

    var errorDescription: String? {
        switch self {
        case .invalidHost(let host):
            "\"\(host)\" doesn't look like a Mastodon instance."
        case .notAuthenticated:
            "You need to sign in again."
        case .server(let status, let message):
            message ?? "The server returned an error (HTTP \(status))."
        case .rateLimited(let retryAfter):
            if let retryAfter {
                "Too many requests. Try again in \(Int(retryAfter.rounded())) seconds."
            } else {
                "Too many requests. Try again shortly."
            }
        case .decoding(let type, _):
            "The server sent a \(type) this app didn't understand."
        case .transport(let message):
            message
        case .unsupported(let feature, let software):
            if let software {
                "\(software) doesn't support \(feature)."
            } else {
                "This instance doesn't support \(feature)."
            }
        }
    }

    var failureReason: String? {
        switch self {
        case .decoding(_, let underlying): underlying
        default: nil
        }
    }

    /// True when the user must sign in again. A second try does not help.
    var requiresReauthentication: Bool {
        switch self {
        case .notAuthenticated: true
        case .server(let status, _): status == 401
        default: false
        }
    }
}

// MARK: - Transport

/// The HTTP layer for one instance. It holds no state.
///
/// The structure is a `Sendable` value with `nonisolated` methods. This is
/// intentional. The client that owns the structure runs on the main actor,
/// but each request runs off the main actor. The JSON decode operation is the
/// slow part, and it also runs off the main actor.
nonisolated struct MastodonHTTP: Sendable {
    let credentials: MastodonCredentials

    private static let logger = Logger(subsystem: "ca.bomberfish.Pachyderm", category: "http")

    /// One session for the full app. The earlier code made a new session for
    /// each request. Thus each request made a new connection, and the URL
    /// cache had no effect.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["Accept": "application/json"]
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = true
        config.urlCache = URLCache(memoryCapacity: 8 << 20, diskCapacity: 64 << 20)
        config.requestCachePolicy = .reloadRevalidatingCacheData
        return URLSession(configuration: config)
    }()

    enum Method: String, Sendable {
        case get = "GET", post = "POST", put = "PUT", patch = "PATCH", delete = "DELETE"
    }

    // MARK: Typed requests

    func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        try decode(await requestData(path, method: .get, query: query))
    }

    func send<T: Decodable>(
        _ path: String,
        method: Method,
        query: [String: String] = [:]
    ) async throws -> T {
        try decode(await requestData(path, method: method, query: query))
    }

    func send<T: Decodable, Body: Encodable>(
        _ path: String,
        method: Method,
        query: [String: String] = [:],
        json: Body
    ) async throws -> T {
        try decode(await requestData(path, method: method, query: query, json: json))
    }

    // MARK: Public documents

    /// Gets a JSON document that is not part of `/api`. NodeInfo is the main
    /// example.
    ///
    /// The request has no access token. These documents need no
    /// authentication, and the server selects the URL of the second request.
    /// Thus a token must not go with it.
    func getPublic<T: Decodable>(path: String) async throws -> T {
        var components = URLComponents()
        components.scheme = "https"
        components.host = try validatedHost()
        components.path = "/" + path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = components.url else {
            throw MastodonError.invalidHost(credentials.host)
        }
        return try await getPublic(url: url)
    }

    /// The same function for a URL from the instance. The `links[].href` value
    /// of NodeInfo is such a URL.
    ///
    /// The URL must use `https`, and it must point to the site of the
    /// instance. Thus a hostile `/.well-known/nodeinfo` document cannot send
    /// the app to a different network.
    func getPublic<T: Decodable>(url: URL) async throws -> T {
        let host = try validatedHost()
        guard url.scheme?.lowercased() == "https",
              let target = url.host?.lowercased(),
              target == host || target.hasSuffix(".\(host)") || host.hasSuffix(".\(target)")
        else {
            throw MastodonError.transport("\(credentials.host) pointed us somewhere unexpected.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = Method.get.rawValue
        return try decode(await perform(request, path: url.path, method: .get))
    }

    private func validatedHost() throws -> String {
        let host = MastodonCredentials.normalize(host: credentials.host)
        guard MastodonCredentials.isValid(host: host) else {
            throw MastodonError.invalidHost(credentials.host)
        }
        return host
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try JSONDecoder.mastodon.decode(T.self, from: data)
        } catch {
            Self.logger.error("Failed to decode \(String(describing: T.self)): \(error)")
            throw MastodonError.decoding(
                type: String(describing: T.self),
                underlying: String(describing: error)
            )
        }
    }

    // MARK: Raw requests

    @discardableResult
    func requestData<Body: Encodable>(
        _ path: String,
        method: Method,
        query: [String: String] = [:],
        json: Body
    ) async throws -> Data {
        try await perform(makeRequest(
            path: path, method: method, query: query,
            body: try JSONEncoder.mastodon.encode(json)
        ), path: path, method: method)
    }

    @discardableResult
    func requestData(
        _ path: String,
        method: Method,
        query: [String: String] = [:]
    ) async throws -> Data {
        try await perform(makeRequest(path: path, method: method, query: query, body: nil),
                          path: path, method: method)
    }

    private func perform(_ request: URLRequest, path: String, method: Method) async throws -> Data {

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await Self.session.data(for: request)
        } catch let error as URLError {
            throw MastodonError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw MastodonError.transport("The server sent a malformed response.")
        }

        Self.logger.debug("\(method.rawValue, privacy: .public) \(path, privacy: .public) -> \(http.statusCode)")

        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 429 {
                let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
                throw MastodonError.rateLimited(retryAfter: retryAfter)
            }
            throw MastodonError.server(status: http.statusCode, message: Self.errorMessage(in: data))
        }

        return data
    }

    // MARK: Request building

    private func makeRequest(
        path: String,
        method: Method,
        query: [String: String],
        body: Data?
    ) throws -> URLRequest {
        let host = try validatedHost()

        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/api/" + path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !query.isEmpty {
            // Sort the items. The URL cache then gets the same key for the
            // same request.
            components.queryItems = query.sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        guard let url = components.url else {
            throw MastodonError.invalidHost(credentials.host)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        if let token = credentials.accessToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        // A method that changes data must not use the cache.
        if method != .get {
            request.cachePolicy = .reloadIgnoringLocalCacheData
        }
        return request
    }

    /// Mastodon sends an error as `{"error": "…", "error_description": "…"}`.
    private static func errorMessage(in data: Data) -> String? {
        guard let payload = try? JSONDecoder.mastodon.decode(ErrorPayload.self, from: data) else {
            return nil
        }
        return payload.errorDescription ?? payload.error
    }
}

private nonisolated struct ErrorPayload: Decodable {
    var error: String?
    var errorDescription: String?
}

extension JSONEncoder {
    nonisolated static let mastodon: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()
}
