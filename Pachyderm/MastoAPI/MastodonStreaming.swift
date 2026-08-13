//
//  MastodonStreaming.swift
//  Pachyderm
//

import Foundation
import Observation
import os

// MARK: - Channels

extension Mastodon {
    /// One channel of `/api/v1/streaming`.
    ///
    /// The channel goes into the `stream` query item. A hashtag channel and a
    /// list channel need a second item.
    nonisolated enum StreamKind: Hashable, Sendable {
        case user
        /// Only the notifications of the user. The `user` channel already
        /// carries them, thus this app does not need a second socket for them.
        case userNotification
        case publicTimeline
        case publicLocal
        case publicRemote
        case direct
        case hashtag(String)
        case list(id: String)

        var name: String {
            switch self {
            case .user: "user"
            case .userNotification: "user:notification"
            case .publicTimeline: "public"
            case .publicLocal: "public:local"
            case .publicRemote: "public:remote"
            case .direct: "direct"
            case .hashtag: "hashtag"
            case .list: "list"
            }
        }

        var queryItems: [URLQueryItem] {
            var items = [URLQueryItem(name: "stream", value: name)]
            switch self {
            case .hashtag(let tag):
                items.append(URLQueryItem(name: "tag", value: tag))
            case .list(let id):
                items.append(URLQueryItem(name: "list", value: id))
            default:
                break
            }
            return items
        }

        /// The channel that carries the same posts as one timeline screen.
        ///
        /// Home uses the `user` channel. That channel also carries the
        /// notifications and the conversations of the user, thus four screens
        /// share one socket.
        ///
        /// Bubble gives nil. Akkoma has no channel for that timeline, thus it
        /// stays a pull-only screen.
        init?(timeline: Mastodon.Timeline) {
            switch timeline {
            case .home: self = .user
            case .local: self = .publicLocal
            case .federated: self = .publicRemote
            case .bubble: return nil
            }
        }
    }

    /// One message from a channel.
    nonisolated enum StreamEvent: Sendable {
        case update(Status)
        /// An edit of a post that can be on the screen.
        case statusUpdate(Status)
        case delete(id: String)
        case notification(Notification)
        case conversation(Conversation)
        /// The filters of the user changed. Each list is now stale.
        case filtersChanged
    }
}

// MARK: - Frames

/// One frame from a channel.
///
/// The `payload` field is unusual: it holds a JSON document inside a JSON
/// string. The decode operation thus has two passes. A `delete` frame is the
/// exception, because its payload is the bare id of a status and not JSON.
private nonisolated struct StreamFrame: Decodable {
    var event: String
    var payload: String?

    private enum CodingKeys: String, CodingKey {
        case event, payload
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        event = try container.decode(String.self, forKey: .event)
        // A frame with no payload is valid: `filters_changed` has none. A fork
        // that sends an object instead of a string gives nil here, and the
        // event below reports the loss. It does not lose the whole socket.
        payload = try? container.decodeIfPresent(String.self, forKey: .payload)
    }
}

// MARK: - Transport

/// The WebSocket layer for one instance. It holds no state.
///
/// The structure mirrors `MastodonHTTP`: a `Sendable` value with `nonisolated`
/// methods. The client that owns it runs on the main actor, and each frame
/// arrives and decodes off the main actor.
nonisolated struct MastodonStreaming: Sendable {
    let credentials: MastodonCredentials
    /// The address from `urls.streaming_api` of `/api/v1/instance`. It is nil
    /// until that request lands, and then the standard path applies.
    let endpoint: URL?

    /// A separate session from the one of `MastodonHTTP`.
    ///
    /// That session has a 30 second request timeout and a URL cache. Both are
    /// correct for a request and response pair. Both are wrong for a socket
    /// that stays open and quiet between two posts.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.waitsForConnectivity = true
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    /// The gap between two pings. A socket with no traffic can stay open on the
    /// device long after the server, or a router between them, dropped it. A
    /// ping that gets no pong turns that silence into an error, and the monitor
    /// then connects again.
    private static let heartbeatInterval: Duration = .seconds(25)

    // MARK: Addresses

    /// Chooses between the address of the instance and the standard path.
    ///
    /// The app must not follow `urls.streaming_api` without a test, because the
    /// access token goes into the query of that address. A hostile instance
    /// document could thus send the token to another network. The test is the
    /// one of `MastodonHTTP.getPublic(url:)`: the same site, a subdomain of it,
    /// or its parent domain.
    func resolvedURL() throws -> URL {
        let host = MastodonCredentials.normalize(host: credentials.host)
        guard MastodonCredentials.isValid(host: host) else {
            throw MastodonError.invalidHost(credentials.host)
        }

        if let endpoint {
            if let url = Self.streamingURL(from: endpoint, host: host) {
                return url
            }
            // Do not log the address. It can hold a token.
            Log.streaming.warning("""
                \(host, privacy: .public) advertised an unusable streaming address. \
                Using the standard path.
                """)
        }

        guard let url = URL(string: "wss://\(host)/api/v1/streaming") else {
            throw MastodonError.invalidHost(credentials.host)
        }
        return url
    }

    /// Accepts an advertised address only when it keeps the token safe: TLS,
    /// and a host on the site of the instance.
    private static func streamingURL(from endpoint: URL, host: String) -> URL? {
        guard let scheme = endpoint.scheme?.lowercased(),
              scheme == "wss" || scheme == "https",
              let target = endpoint.host?.lowercased(),
              target == host || target.hasSuffix(".\(host)") || host.hasSuffix(".\(target)"),
              var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        else { return nil }

        components.scheme = "wss"
        // Some instances give the bare origin, others give the full path.
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = path.isEmpty ? "/api/v1/streaming" : "/" + path
        components.query = nil
        components.fragment = nil
        return components.url
    }

    /// The token goes into the query and into a header.
    ///
    /// Mastodon reads the header. GoToSocial, the Pleroma family and the older
    /// streaming servers read only the query item. Both together work
    /// everywhere.
    private func request(for kind: Mastodon.StreamKind) throws -> URLRequest {
        guard var components = URLComponents(url: try resolvedURL(), resolvingAgainstBaseURL: false) else {
            throw MastodonError.invalidHost(credentials.host)
        }

        let token = credentials.accessToken ?? ""
        var items = kind.queryItems
        if !token.isEmpty {
            items.append(URLQueryItem(name: "access_token", value: token))
        }
        components.queryItems = items

        guard let url = components.url else {
            throw MastodonError.invalidHost(credentials.host)
        }

        var request = URLRequest(url: url)
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    // MARK: Events

    /// Opens one socket and gives each event of it.
    ///
    /// The function makes one attempt. The stream ends when the server closes
    /// the socket, and it throws when the connection fails. The retry policy is
    /// in `MastodonStreamMonitor`, because a policy needs state and this
    /// structure has none.
    func events(for kind: Mastodon.StreamKind) -> AsyncThrowingStream<Mastodon.StreamEvent, any Error> {
        AsyncThrowingStream { continuation in
            let socket: URLSessionWebSocketTask
            do {
                socket = Self.session.webSocketTask(with: try request(for: kind))
            } catch {
                continuation.finish(throwing: error)
                return
            }

            let pump = Task {
                socket.resume()

                let heartbeat = Task {
                    while !Task.isCancelled {
                        try await Task.sleep(for: Self.heartbeatInterval)
                        try await Self.ping(socket)
                    }
                }
                defer { heartbeat.cancel() }

                do {
                    while !Task.isCancelled {
                        let message = try await socket.receive()
                        if let event = Self.event(in: message) {
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                pump.cancel()
                socket.cancel(with: .goingAway, reason: nil)
            }
        }
    }

    /// The async form of `sendPing`. Foundation offers only the closure form.
    /// The closure runs when the pong arrives, thus the call is a full round
    /// trip and not only a write.
    private static func ping(_ socket: URLSessionWebSocketTask) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            socket.sendPing { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private static func event(in message: URLSessionWebSocketTask.Message) -> Mastodon.StreamEvent? {
        switch message {
        case .data(let data): event(in: data)
        case .string(let text): event(in: Data(text.utf8))
        @unknown default: nil
        }
    }

    /// Turns one frame into an event. An unusable frame gives nil, because one
    /// bad frame must not close a socket that works.
    static func event(in data: Data) -> Mastodon.StreamEvent? {
        guard let frame = try? JSONDecoder.mastodon.decode(StreamFrame.self, from: data) else {
            Log.streaming.error("A frame arrived without a readable envelope.")
            return nil
        }

        switch frame.event {
        case "delete":
            // The payload is the bare id of the status. It is not a JSON
            // document, thus it must not reach the decoder.
            guard let id = frame.payload, !id.isEmpty else { return nil }
            return .delete(id: id)
        case "filters_changed":
            return .filtersChanged
        default:
            break
        }

        guard let payload = frame.payload.map({ Data($0.utf8) }) else {
            Log.streaming.error("A \(frame.event, privacy: .public) frame had no payload.")
            return nil
        }

        do {
            switch frame.event {
            case "update":
                return .update(try JSONDecoder.mastodon.decode(Mastodon.Status.self, from: payload))
            case "status.update":
                return .statusUpdate(try JSONDecoder.mastodon.decode(Mastodon.Status.self, from: payload))
            case "notification":
                return .notification(try JSONDecoder.mastodon.decode(Mastodon.Notification.self, from: payload))
            case "conversation":
                return .conversation(try JSONDecoder.mastodon.decode(Mastodon.Conversation.self, from: payload))
            default:
                // `announcement`, `announcement.reaction`, `encrypted_message`
                // and the events of a fork arrive here. This app has no screen
                // for them.
                Log.streaming.debug("Ignoring a \(frame.event, privacy: .public) event.")
                return nil
            }
        } catch {
            Log.streaming.error("""
                A \(frame.event, privacy: .public) payload didn't decode: \
                \(error.localizedDescription, privacy: .public)
                """)
            return nil
        }
    }
}

// MARK: - Monitor

/// Keeps one channel open and hands its events to a screen.
///
/// `MastodonStreaming` makes one attempt. This class holds the policy. It
/// connects again after a failure, and it waits longer after each subsequent
/// failure. An instance that restarts thus gets a small number of requests, and
/// not one request in each pass of the run loop.
@MainActor
@Observable
final class MastodonStreamMonitor {
    enum State: Equatable {
        case idle
        case connected
        /// The socket is closed. The value says why.
        case offline(String)
    }

    private(set) var state: State = .idle

    /// Runs before each attempt that follows a connection that worked.
    ///
    /// The screen saw none of the events in the gap, thus it must load its
    /// first page again. The delay before the attempt limits how often this
    /// closure can run.
    var onReconnect: (@MainActor () async -> Void)?

    /// The shortest wait after a failure, in seconds. Each subsequent failure
    /// doubles it, up to the maximum.
    private static let firstDelay: Double = 1
    private static let maximumDelay: Double = 30
    /// A connection that stays open at least this long counted as a good one,
    /// even when it carried no event. A quiet timeline is normal.
    private static let successfulDuration: Duration = .seconds(30)

    private let streaming: MastodonStreaming
    private let kind: Mastodon.StreamKind
    private var task: Task<Void, Never>?

    init(streaming: MastodonStreaming, kind: Mastodon.StreamKind) {
        self.streaming = streaming
        self.kind = kind
    }

    var isRunning: Bool { task != nil }

    /// Opens the channel. A second call does nothing while the first one runs.
    func start(onEvent: @MainActor @escaping (Mastodon.StreamEvent) async -> Void) {
        guard task == nil else { return }
        task = Task { [weak self] in
            await self?.run(onEvent: onEvent)
        }
    }

    /// Closes the channel. The caller must call it, because the loop keeps this
    /// object alive while it runs.
    func stop() {
        task?.cancel()
        task = nil
        state = .idle
    }

    private func run(onEvent: @MainActor @escaping (Mastodon.StreamEvent) async -> Void) async {
        var failures = 0
        var hasConnected = false

        while !Task.isCancelled {
            if hasConnected {
                await onReconnect?()
                guard !Task.isCancelled else { break }
            }

            let started = ContinuousClock.now
            var carriedEvent = false
            state = .connected

            do {
                for try await event in streaming.events(for: kind) {
                    carriedEvent = true
                    await onEvent(event)
                }
                guard !Task.isCancelled else { break }
                state = .offline("The server closed the connection.")
                Log.streaming.info("\(self.kind.name, privacy: .public): the server closed the socket.")
            } catch is CancellationError {
                break
            } catch {
                guard !Task.isCancelled else { break }
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                state = .offline(message)
                Log.streaming.error("\(self.kind.name, privacy: .public): \(message, privacy: .public)")
            }

            guard !Task.isCancelled else { break }

            // A connection that carried an event, or that lasted a while, was a
            // good one. The next failure then waits from the shortest delay
            // again, rather than from the length of an old outage.
            if carriedEvent || ContinuousClock.now - started >= Self.successfulDuration {
                hasConnected = true
                failures = 0
            }

            failures += 1
            let delay = min(Self.maximumDelay, Self.firstDelay * pow(2, Double(failures - 1)))
            try? await Task.sleep(for: .seconds(delay))
        }

        state = .idle
    }
}
