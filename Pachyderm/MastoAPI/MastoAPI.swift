//
//  MastoAPI.swift
//  Pachyderm
//
//  Created by Hariz Shirazi on 2025-06-12.
//

import Foundation
import Observation
import os


@MainActor
@Observable
final class MastoAPI {
    /// The account of the user. `logIn` and `refreshCurrentAccount()` set it.
    private(set) var currentAccount: Mastodon.Account?

    private(set) var credentials: MastodonCredentials
    
    private(set) var instance: Mastodon.Instance?

    /// The abilities of the software of this instance. The value starts from
    /// the stored data for the current host. Thus the user interface can show
    /// the correct controls in the first frame. A refresh follows.
    private(set) var capabilities = APICapabilities.unknown

    private static let logger = Logger(subsystem: "ca.bomberfish.Pachyderm", category: "api")

    private enum StorageKey {
        static let host = "instanceHost"
        static let token = "accessToken"
        /// The keys of an earlier build. That build put both values in
        /// `UserDefaults`.
        static let legacyHost = "baseURL"
        static let legacyToken = "accessToken"

        static func capabilities(for host: String) -> String { "capabilities.\(host)" }
    }

    var host: String { credentials.host }
    var isAuthenticated: Bool { credentials.isAuthenticated }

    private var http: MastodonHTTP { MastodonHTTP(credentials: credentials) }

    // MARK: - Session

    init() {
        credentials = Self.loadCredentials()
        capabilities = Self.loadCapabilities(for: credentials.host)
    }

    /// The initializer for a preview and for a test. It makes a client and it
    /// does not read the stored data.
    init(credentials: MastodonCredentials, capabilities: APICapabilities = .unknown) {
        self.credentials = credentials
        self.capabilities = capabilities
    }

    private static func loadCredentials() -> MastodonCredentials {
        let defaults = UserDefaults.standard
        let stored = defaults.string(forKey: StorageKey.host)
            ?? defaults.string(forKey: StorageKey.legacyHost)
            ?? ""
        let host = MastodonCredentials.normalize(host: stored)

        // Do this migration one time. An earlier build put the token in
        // `UserDefaults`. Move that token into the keychain. Then delete the
        // copy that has no encryption.
        if let legacy = defaults.string(forKey: StorageKey.legacyToken), !legacy.isEmpty {
            Keychain.set(legacy, for: StorageKey.token)
            defaults.removeObject(forKey: StorageKey.legacyToken)
            logger.info("Migrated the access token from UserDefaults into the keychain.")
        }
        defaults.removeObject(forKey: StorageKey.legacyHost)
        defaults.set(host, forKey: StorageKey.host)

        return MastodonCredentials(host: host, accessToken: Keychain.string(for: StorageKey.token))
    }

    func logIn(host: String, accessToken: String) async throws {
        let normalized = MastodonCredentials.normalize(host: host)
        guard MastodonCredentials.isValid(host: normalized) else {
            throw MastodonError.invalidHost(host)
        }

        let candidate = MastodonCredentials(host: normalized, accessToken: accessToken)
        let account: Mastodon.Account = try await MastodonHTTP(credentials: candidate)
            .get("v1/accounts/verify_credentials")

        credentials = candidate
        currentAccount = account
        capabilities = Self.loadCapabilities(for: normalized)
        UserDefaults.standard.set(normalized, forKey: StorageKey.host)
        Keychain.set(accessToken, for: StorageKey.token)

        // These are two more requests. The user must not wait for them.
        Task { await refreshInstance() }
    }

    func logOut() {
        credentials = MastodonCredentials(host: credentials.host, accessToken: nil)
        currentAccount = nil
        Keychain.remove(StorageKey.token)
    }

    @discardableResult
    func refreshCurrentAccount() async throws -> Mastodon.Account {
        try requireAuthentication()
        let account: Mastodon.Account = try await http.get("v1/accounts/verify_credentials")
        currentAccount = account
        return account
    }

    // MARK: - Timelines

    /// - Parameter olderThan: The id of the oldest status on the screen. The
    ///   server sends the subsequent page after this status.
    func statuses(
        in timeline: Mastodon.Timeline,
        olderThan: String? = nil,
        limit: Int = 40
    ) async throws -> [Mastodon.Status] {
        try requireAuthentication()
        var query = timeline.query
        query["limit"] = String(limit)
        if let olderThan { query["max_id"] = olderThan }
        return try await http.get(timeline.path, query: query)
    }

    func statuses(
        byAccount id: String,
        feed: Mastodon.AccountFeed,
        olderThan: String? = nil,
        limit: Int = 40
    ) async throws -> [Mastodon.Status] {
        try requireAuthentication()
        var query = feed.query
        query["limit"] = String(limit)
        if let olderThan { query["max_id"] = olderThan }
        return try await http.get("v1/accounts/\(id)/statuses", query: query)
    }

    func notifications(olderThan: String? = nil, limit: Int = 40) async throws -> [Mastodon.Notification] {
        try requireAuthentication()
        var query = ["limit": String(limit)]
        if let olderThan { query["max_id"] = olderThan }
        return try await http.get("v1/notifications", query: query)
    }
    
    func unreadNotificationCount() async throws -> Mastodon.UnreadNotificationCount {
        try requireAuthentication()
        return try await http.get("v1/notifications/unread_count");
    }

    func conversations(olderThan: String? = nil, limit: Int = 40) async throws -> [Mastodon.Conversation] {
        try requireAuthentication()
        var query = ["limit": String(limit)]
        if let olderThan { query["max_id"] = olderThan }
        return try await http.get("v1/conversations", query: query)
    }

    // MARK: - Lookups

    func status(id: String) async throws -> Mastodon.Status {
        try requireAuthentication()
        return try await http.get("v1/statuses/\(id)")
    }

    /// The thread of a status. The parent posts come in date order, oldest
    /// first. The replies come in reply order.
    func context(of id: String) async throws -> Mastodon.Context {
        try requireAuthentication()
        return try await http.get("v1/statuses/\(id)/context")
    }

    func account(id: String) async throws -> Mastodon.Account {
        try requireAuthentication()
        return try await http.get("v1/accounts/\(id)")
    }

    func search(_ query: String, limit: Int = 20) async throws -> Mastodon.SearchResults {
        try requireAuthentication()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Mastodon.SearchResults(accounts: [], statuses: [], hashtags: [])
        }
        return try await http.get("v2/search", query: [
            "q": trimmed,
            "limit": String(limit),
            "resolve": "true",
        ])
    }

    // MARK: - Instance

    func instance(host: String? = nil) async throws -> Mastodon.Instance {
        guard let host else {
            return try await http.get("v1/instance")
        }

        let target = MastodonCredentials.normalize(host: host)
        guard MastodonCredentials.isValid(host: target) else {
            throw MastodonError.invalidHost(host)
        }
        // Send the token only to the instance of the user. A token for host A
        // must not go to host B.
        let credentials = target == self.credentials.host
            ? self.credentials
            : MastodonCredentials(host: target, accessToken: nil)
        return try await MastodonHTTP(credentials: credentials).get("v1/instance")
    }

    /// Gets `/.well-known/nodeinfo` and then the document that it points to.
    ///
    /// This function makes two requests. The requests have no access token.
    /// This is intentional. Refer to `MastodonHTTP.getPublic`.
    func nodeInfo(host: String? = nil) async throws -> NodeInfo {
        let target = MastodonCredentials.normalize(host: host ?? credentials.host)
        guard MastodonCredentials.isValid(host: target) else {
            throw MastodonError.invalidHost(host ?? credentials.host)
        }
        let http = MastodonHTTP(credentials: MastodonCredentials(host: target, accessToken: nil))

        let index: NodeInfoIndex = try await http.getPublic(path: ".well-known/nodeinfo")
        guard let href = index.preferredHref else {
            throw MastodonError.transport("\(target) doesn't publish a NodeInfo document.")
        }
        return try await http.getPublic(url: href)
    }

    // MARK: - Streaming

    /// The `wss://` address from `/api/v1/instance`. It is nil until that
    /// request lands, and `MastodonStreaming` then uses the standard path.
    var streamingEndpoint: URL? { instance?.urls?.streamingURL }

    func streaming() -> MastodonStreaming {
        MastodonStreaming(credentials: credentials, endpoint: streamingEndpoint)
    }

    /// The tolerant test. An unknown fork gets one attempt. A timeline that
    /// never updates on its own is worse than one line in the log.
    var supportsStreaming: Bool { supportsOrUnknown(.streaming) }

    // MARK: - Capabilities

    /// Refreshes `instance` and `capabilities` for the current host.
    ///
    /// The function does the maximum that it can, but it does not fail. It
    /// only adds data about the server. A server that answers neither request
    /// stays usable.
    @discardableResult
    func refreshInstance() async -> APICapabilities {
        // NodeInfo is the primary source. Each fork gives correct data in that
        // document. `/api/v1/instance` completes the missing data, and it also
        // gives the post limits.
        async let fetchedNode = try? nodeInfo()
        async let fetchedInstance = try? instance()

        let node = await fetchedNode
        let details = await fetchedInstance

        var detected = node.map(APICapabilities.init(nodeInfo:)) ?? .unknown
        if let details {
            instance = details
            detected = detected.merging(APICapabilities(instance: details))
        }

        capabilities = detected
        Self.store(detected, for: credentials.host)
        Self.logger.info("\(self.credentials.host, privacy: .public) is \(detected.summary, privacy: .public)")
        return detected
    }

    /// Makes no request when this launch has the data.
    func refreshInstanceIfNeeded() async {
        guard instance == nil || !capabilities.isDetected else { return }
        await refreshInstance()
    }

    /// Tells you if the app can offer an optional feature. An unknown server
    /// gives `false`. Thus use this function only for an added feature.
    func supports(_ requirements: APICapabilityRequirements) -> Bool {
        capabilities.satisfies(requirements)
    }

    /// The tolerant function. It gives `true`, except when the app knows that
    /// the server does not have the feature. Use it for a feature that has
    /// correct code. A hidden control on an unknown fork is worse than one
    /// error message.
    func supportsOrUnknown(_ requirements: APICapabilityRequirements) -> Bool {
        !capabilities.isDetected || capabilities.satisfies(requirements)
    }

    /// Stops a request before the app sends it, and gives a clear message. The
    /// alternative is an unclear message from the server about an unknown
    /// endpoint.
    func requireSupport(_ requirements: APICapabilityRequirements, for feature: String) throws {
        guard !supportsOrUnknown(requirements) else { return }
        throw MastodonError.unsupported(feature: feature, software: capabilities.summary)
    }

    private static func loadCapabilities(for host: String) -> APICapabilities {
        guard !host.isEmpty,
              let data = UserDefaults.standard.data(forKey: StorageKey.capabilities(for: host)),
              let stored = try? JSONDecoder().decode(APICapabilities.self, from: data)
        else { return .unknown }
        return stored
    }

    private static func store(_ capabilities: APICapabilities, for host: String) {
        guard !host.isEmpty else { return }
        let key = StorageKey.capabilities(for: host)
        guard capabilities != .unknown, let data = try? JSONEncoder().encode(capabilities) else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        UserDefaults.standard.set(data, forKey: key)
    }

    // MARK: - Publishing

    @discardableResult
    func post(
        _ text: String,
        visibility: Mastodon.Visibility = .public,
        spoilerText: String? = nil,
        inReplyTo: String? = nil
    ) async throws -> Mastodon.Status {
        try requireAuthentication()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw MastodonError.server(status: 422, message: "A post can't be empty.")
        }
        let warning = spoilerText?.trimmingCharacters(in: .whitespacesAndNewlines)

        return try await http.send("v1/statuses", method: .post, json: NewStatus(
            status: trimmed,
            // The value `.unknown` comes only from the post of a different
            // user. Test the value here, because the server must not get an
            // incorrect visibility value.
            visibility: (visibility == .unknown ? .public : visibility).rawValue,
            spoilerText: (warning?.isEmpty == false) ? warning : nil,
            inReplyToId: inReplyTo
        ))
    }

    // MARK: - Interactions

    /// Sets the favourite flag. It gives the new status from the server.
    func setFavourited(_ favourited: Bool, on status: Mastodon.Status) async throws -> Mastodon.Status {
        try await interact(with: status, action: favourited ? "favourite" : "unfavourite")
    }

    func setReblogged(_ reblogged: Bool, on status: Mastodon.Status) async throws -> Mastodon.Status {
        let result = try await interact(with: status, action: reblogged ? "reblog" : "unreblog")
        return result.reblog?.value ?? result
    }

    func setBookmarked(_ bookmarked: Bool, on status: Mastodon.Status) async throws -> Mastodon.Status {
        try await interact(with: status, action: bookmarked ? "bookmark" : "unbookmark")
    }

    private func interact(with status: Mastodon.Status, action: String) async throws -> Mastodon.Status {
        try requireAuthentication()
        return try await http.send("v1/statuses/\(status.id)/\(action)", method: .post)
    }

    // MARK: - Helpers

    private func requireAuthentication() throws {
        guard credentials.isAuthenticated else { throw MastodonError.notAuthenticated }
    }
}

/// The body of a `POST /api/v1/statuses` request.
private nonisolated struct NewStatus: Encodable {
    var status: String
    var visibility: String
    var spoilerText: String?
    var inReplyToId: String?
}
