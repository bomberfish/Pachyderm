//
//  MastodonModels.swift
//  Pachyderm
//
//  Created by Hariz Shirazi on 2025-06-12.
//

import Foundation


enum Mastodon {}

// MARK: - Account

extension Mastodon {
    nonisolated struct Account: Codable, Identifiable, Hashable, Sendable {
        var id: String
        var username: String
        /// `user` for an account on this instance. `user@remote.example` for
        /// an account on a different instance.
        var acct: String
        var displayName: String
        var note: String?
        var url: String?
        var avatar: String?
        var avatarStatic: String?
        var header: String?
        var headerStatic: String?
        var followersCount: Int?
        var followingCount: Int?
        var statusesCount: Int?
        var locked: Bool?
        var bot: Bool?
        var createdAt: Date?
        var lastStatusAt: Date?
        var emojis: [Emoji]?
        var fields: [Field]?

        /// Gives the username when the display name is empty. Many accounts
        /// have no display name.
        var bestDisplayName: String {
            displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? username : displayName
        }

        var avatarURL: URL? { URL(string: avatar ?? "") }
        var headerURL: URL? { URL(string: header ?? "") }

        nonisolated struct Field: Codable, Hashable, Sendable, Identifiable {
            var name: String
            var value: String
            var verifiedAt: Date?

            var id: String { name + value }
            var isVerified: Bool { verifiedAt != nil }
        }
    }
}

// MARK: - Status

extension Mastodon {
    nonisolated struct Status: Codable, Identifiable, Hashable, Sendable {
        var id: String
        var uri: String?
        var url: String?
        var createdAt: Date?
        var editedAt: Date?
        var content: String?
        var spoilerText: String?
        var visibility: Visibility?
        var sensitive: Bool?
        var language: String?

        var account: Account
        var reblog: Indirect<Status>?

        var repliesCount: Int
        var reblogsCount: Int
        var favouritesCount: Int

        var favourited: Bool?
        var reblogged: Bool?
        var bookmarked: Bool?
        var muted: Bool?
        var pinned: Bool?

        var inReplyToId: String?
        var inReplyToAccountId: String?

        var mediaAttachments: [MediaAttachment]?
        var mentions: [Mention]?
        var tags: [Tag]?
        var emojis: [Emoji]?
        var card: Card?
        var poll: Poll?

        // The extensions of the forks: glitch-soc, Akkoma, Chuckya and others.
        // Mastodon does not send these fields.
        var localOnly: Bool?
        var reactions: [Reaction]?

        /// The status with the content for the screen. A boost holds a
        /// different status. This property gives that status.
        var displayed: Status { reblog?.value ?? self }

        var html: String { content ?? "" }
        var attachments: [MediaAttachment] { mediaAttachments ?? [] }

        /// The account that made the boost. It is nil for a usual post.
        var boostedBy: Account? { reblog == nil ? nil : account }

        var hasContentWarning: Bool {
            !(spoilerText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        var permalink: URL? { URL(string: url ?? uri ?? "") }
    }
}

// MARK: - Status visibility

extension Mastodon {
    nonisolated enum Visibility: String, Codable, Hashable, Sendable {
        case `public`
        case unlisted
        case `private`
        case direct
        /// A visibility of one software that this app does not know.
        case unknown

        /// The visibility values in the compose screen. The first value gives
        /// the maximum number of readers.
        static let composable: [Visibility] = [.public, .unlisted, .private, .direct]

        init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            // An unknown value does not cause an error. But it becomes
            // `.unknown`, not `.public`. Thus the app cannot show that a post
            // has more readers than the true number.
            self = Visibility(rawValue: raw) ?? .unknown
        }

        var description: String {
            switch self {
            case .public: "Public"
            case .unlisted: "Quiet public"
            case .private: "Followers only"
            case .direct: "Private mention"
            case .unknown: "Unknown"
            }
        }

        var icon: String {
            switch self {
            case .public: "globe"
            case .unlisted: "moon"
            case .private: "lock"
            case .direct: "at"
            case .unknown: "questionmark"
            }
        }
    }
}

// MARK: - Attachments

extension Mastodon {
    nonisolated struct MediaAttachment: Codable, Identifiable, Hashable, Sendable {
        var id: String
        var type: Kind
        var url: String?
        var previewUrl: String?
        var remoteUrl: String?
        /// The text for a screen reader.
        var description: String?
        /// A BlurHash value. It gives an image before the load operation ends.
        var blurhash: String?
        var meta: Meta?

        var mediaURL: URL? { URL(string: url ?? remoteUrl ?? "") }
        var previewURL: URL? { URL(string: previewUrl ?? url ?? "") }

        /// The width divided by the height of the original file. It is nil when
        /// the server gives no size.
        var aspectRatio: Double? {
            guard let size = meta?.original,
                  let width = size.width, let height = size.height, height > 0
            else { return nil }
            return Double(width) / Double(height)
        }

        nonisolated enum Kind: String, Codable, Hashable, Sendable {
            case image, video, gifv, audio, unknown

            init(from decoder: any Decoder) throws {
                let raw = try decoder.singleValueContainer().decode(String.self)
                self = Kind(rawValue: raw) ?? .unknown
            }

            /// A `gifv` file is an MP4 file. It plays again and again, and it
            /// has no sound.
            var isVideo: Bool { self == .video || self == .gifv }
        }

        nonisolated struct Meta: Codable, Hashable, Sendable {
            var original: Size?
            var small: Size?

            nonisolated struct Size: Codable, Hashable, Sendable {
                var width: Int?
                var height: Int?
                var duration: Double?
            }
        }
    }
}

// MARK: - Inline entities

extension Mastodon {
    nonisolated struct Emoji: Codable, Hashable, Sendable, Identifiable {
        var shortcode: String
        var url: String?
        var staticUrl: String?
        var visibleInPicker: Bool?

        var id: String { shortcode }
        /// Selects the image with no movement. Emoji with movement in a
        /// timeline use much battery power.
        var imageURL: URL? { URL(string: staticUrl ?? url ?? "") }
    }

    nonisolated struct Mention: Codable, Hashable, Sendable, Identifiable {
        var id: String
        var username: String
        var url: String?
        var acct: String?
    }

    nonisolated struct Tag: Codable, Hashable, Sendable, Identifiable {
        var name: String
        var url: String?

        var id: String { name }
    }

    nonisolated struct Reaction: Codable, Hashable, Sendable, Identifiable {
        var name: String
        var count: Int
        var me: Bool?
        var url: String?
        var staticUrl: String?

        var id: String { name }
        var customImageURL: URL? { URL(string: staticUrl ?? url ?? "") }
    }
}

// MARK: - Attached objects

extension Mastodon {
    nonisolated struct Card: Codable, Hashable, Sendable {
        var url: String
        var title: String
        var description: String?
        var type: String?
        var image: String?
        var providerName: String?

        var linkURL: URL? { URL(string: url) }
        var imageURL: URL? { URL(string: image ?? "") }
    }

    nonisolated struct Poll: Codable, Identifiable, Hashable, Sendable {
        var id: String
        var expiresAt: Date?
        var expired: Bool
        var multiple: Bool
        var votesCount: Int
        var votersCount: Int?
        var voted: Bool?
        var ownVotes: [Int]?
        var options: [Option]

        nonisolated struct Option: Codable, Hashable, Sendable, Identifiable {
            var title: String
            var votesCount: Int?

            var id: String { title }
        }

        /// The part of the votes for one option, from 0 to 1. It is nil when
        /// the server hides the results.
        func share(of option: Option) -> Double? {
            guard let votes = option.votesCount, votesCount > 0 else { return nil }
            return Double(votes) / Double(votesCount)
        }
    }
}

// MARK: - Notifications

extension Mastodon {
    nonisolated struct UnreadNotificationCount: Codable, Hashable, Sendable {
        var count: Int
    }
    
    nonisolated struct Notification: Codable, Identifiable, Hashable, Sendable {
        var id: String
        var type: Kind
        var createdAt: Date?
        var account: Account
        var status: Status?

        nonisolated enum Kind: String, Codable, Hashable, Sendable {
            case mention, status, reblog, follow, followRequest, favourite
            case poll, update, adminSignUp, adminReport, severedRelationships
            case moderationWarning
            case unknown

            init(from decoder: any Decoder) throws {
                let raw = try decoder.singleValueContainer().decode(String.self)
                // The key decode strategy does not change a value, only a key.
                // Thus a value such as `follow_request` needs this change
                // here.
                self = Kind(rawValue: raw) ?? Kind(rawValue: raw.camelCased) ?? .unknown
            }

            var icon: String {
                switch self {
                case .mention: "at"
                case .status: "bell"
                case .reblog: "arrow.2.squarepath"
                case .follow, .followRequest: "person.badge.plus"
                case .favourite: "star.fill"
                case .poll: "chart.bar"
                case .update: "pencil"
                case .adminSignUp, .adminReport: "shield"
                case .severedRelationships, .moderationWarning: "exclamationmark.triangle"
                case .unknown: "questionmark"
                }
            }

            func summary(for account: Account) -> String {
                let who = account.bestDisplayName
                switch self {
                case .mention: return "\(who) mentioned you"
                case .status: return "\(who) posted"
                case .reblog: return "\(who) boosted your post"
                case .follow: return "\(who) followed you"
                case .followRequest: return "\(who) asked to follow you"
                case .favourite: return "\(who) favourited your post"
                case .poll: return "A poll you took part in has ended"
                case .update: return "\(who) edited a post"
                case .adminSignUp: return "\(who) signed up"
                case .adminReport: return "\(who) filed a report"
                case .severedRelationships: return "Some of your relationships were severed"
                case .moderationWarning: return "You received a moderation warning"
                case .unknown: return "Notification from \(who)"
                }
            }
        }
    }
}

// MARK: - Threads

extension Mastodon {
    /// The posts near a status. These are the parent posts and the replies.
    nonisolated struct Context: Codable, Hashable, Sendable {
        var ancestors: [Status]
        var descendants: [Status]

        static let empty = Context(ancestors: [], descendants: [])
    }
}

// MARK: - Direct messages

extension Mastodon {
    /// A thread of private messages from `/api/v1/conversations`.
    nonisolated struct Conversation: Codable, Identifiable, Hashable, Sendable {
        var id: String
        var unread: Bool
        var accounts: [Account]
        var lastStatus: Status?

        /// The names of the other persons in the thread. The API does not
        /// include the account of the user.
        var title: String {
            accounts.isEmpty
                ? "Just you"
                : accounts.map(\.bestDisplayName).formatted(.list(type: .and))
        }
    }
}

// MARK: - Search

extension Mastodon {
    nonisolated struct SearchResults: Codable, Hashable, Sendable {
        var accounts: [Account]
        var statuses: [Status]
        var hashtags: [Tag]

        var isEmpty: Bool { accounts.isEmpty && statuses.isEmpty && hashtags.isEmpty }
    }
}

// MARK: - Instance

extension Mastodon {
    /// The data about a server from `/api/v1/instance`.
    ///
    /// Nearly all the fields are optional. This is intentional. Mastodon 4.0
    /// made this document obsolete and added `/api/v2/instance`. The forks that
    /// keep the old document each remove different fields. Pleroma, Akkoma,
    /// GoToSocial and Iceshrimp are examples. Thus a field that is not present
    /// must give the default value from the documents. It must not cause an
    /// error that removes all the data about the server.
    nonisolated struct Instance: Codable, Hashable, Sendable {
        /// The domain of the instance. It can be different from the host in
        /// the request.
        var uri: String?
        var title: String?
        var shortDescription: String?
        var description: String?
        var email: String?
        var version: String?
        var languages: [String]?
        var thumbnail: String?
        var registrations: Bool?
        var approvalRequired: Bool?
        var invitesEnabled: Bool?
        var stats: Stats?
        var urls: URLs?
        var configuration: Configuration?
        /// Pleroma and Akkoma give the post limit in this field. They do not
        /// use `configuration.statuses`. Their limit is usually not 500.
        var maxTootChars: Int?
        var contactAccount: Account?
        var rules: [Rule]?

        nonisolated struct Stats: Codable, Hashable, Sendable {
            var userCount: Int?
            var statusCount: Int?
            var domainCount: Int?
        }

        nonisolated struct URLs: Codable, Hashable, Sendable {
            /// A `wss://` address for the streaming API.
            var streamingApi: String?

            var streamingURL: URL? { URL(string: streamingApi ?? "") }
        }

        nonisolated struct Configuration: Codable, Hashable, Sendable {
            var statuses: Statuses?
            var mediaAttachments: MediaAttachments?
            var polls: Polls?

            nonisolated struct Statuses: Codable, Hashable, Sendable {
                var maxCharacters: Int?
                var maxMediaAttachments: Int?
                var charactersReservedPerUrl: Int?
            }

            nonisolated struct MediaAttachments: Codable, Hashable, Sendable {
                var supportedMimeTypes: [String]?
                var imageSizeLimit: Int?
                var imageMatrixLimit: Int?
                var videoSizeLimit: Int?
                var videoFrameRateLimit: Int?
                var videoMatrixLimit: Int?
            }

            nonisolated struct Polls: Codable, Hashable, Sendable {
                var maxOptions: Int?
                var maxCharactersPerOption: Int?
                var minExpiration: Int?
                var maxExpiration: Int?
            }
        }

        nonisolated struct Rule: Codable, Identifiable, Hashable, Sendable {
            var id: String
            var text: String
            /// Mastodon 4.3 added this field.
            var hint: String?
        }

        // MARK: Convenience

        /// Only the host. The property removes a scheme and a final slash from
        /// the value of the server.
        var domain: String? {
            guard let uri else { return nil }
            let host = MastodonCredentials.normalize(host: uri)
            return host.isEmpty ? nil : host
        }

        /// A name for a header. The property always gives a usable name.
        var displayName: String {
            for candidate in [title, domain, uri] {
                if let candidate, !candidate.isEmpty { return candidate }
            }
            return "This instance"
        }

        /// The short description. It gives the long description when the short
        /// description is empty.
        var blurb: String? {
            for candidate in [shortDescription, description] {
                if let candidate, !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return candidate
                }
            }
            return nil
        }

        var thumbnailURL: URL? { URL(string: thumbnail ?? "") }

        /// The maximum length of a post. Glitch-soc, GoToSocial and the Pleroma
        /// family use a much higher limit than the 500 characters of Mastodon.
        var maxPostCharacters: Int {
            configuration?.statuses?.maxCharacters ?? maxTootChars ?? 500
        }

        /// Each link uses this number of characters. The true length of the
        /// link has no effect.
        var charactersReservedPerURL: Int { configuration?.statuses?.charactersReservedPerUrl ?? 23 }

        var maxMediaAttachments: Int { configuration?.statuses?.maxMediaAttachments ?? 4 }

        /// True when the server accepts a new account, and an administrator
        /// does not have to approve it.
        var isOpenForSignUps: Bool { (registrations ?? false) && !(approvalRequired ?? false) }
    }
}

// MARK: - Feeds

extension Mastodon {
    /// The public timelines that this app can show.
    ///
    /// Each case holds its own query parameters. The parameters are not part of
    /// the path. The earlier code put them in the path. Thus a request for a
    /// subsequent page lost the `remote` filter and the `local` filter after
    /// the code added a `max_id` parameter.
    nonisolated enum Timeline: String, CaseIterable, Identifiable, Hashable, Sendable {
        case home, local, federated, bubble
        
        @MainActor public static func validCases(_ api: MastoAPI) -> [Self] {
            var available: [Self] = [.home, .local, .federated]
            if let flavor = api.capabilities.flavor {
                if flavor == .akkoma || flavor == .chuckya {
                    available.append(.bubble)
                }
            }
            return available
        }

        var id: String { rawValue }

        var path: String {
            switch self {
            case .home: "v1/timelines/home"
            case .local, .federated, .bubble: "v1/timelines/public"
            }
        }

        var query: [String: String] {
            switch self {
            case .home: [:]
            case .local: ["local": "true"]
            case .federated: ["remote": "true"]
            case .bubble: ["bubble": "true"]
            }
        }

        var description: String {
            switch self {
            case .home: "Home"
            case .local: "Local"
            case .federated: "Federated"
            case .bubble: "Bubble"
            }
        }

        var icon: String {
            switch self {
            case .home: "house"
            case .local: "building.2"
            case .federated: "globe"
            case .bubble: "bubbles.and.sparkles"
            }
        }
    }

    /// The group of posts to show on a profile screen.
    nonisolated enum AccountFeed: String, CaseIterable, Identifiable, Hashable, Sendable {
        case posts, replies, media

        var id: String { rawValue }

        var query: [String: String] {
            switch self {
            case .posts: ["exclude_replies": "true"]
            case .replies: [:]
            case .media: ["only_media": "true"]
            }
        }

        var description: String {
            switch self {
            case .posts: "Posts"
            case .replies: "Replies"
            case .media: "Media"
            }
        }
    }
}

// MARK: - Indirect

/// A box in the heap. It lets a value type contain a value of its own type.
///
/// The `Mastodon.Status.reblog` property holds a `Status` value. Without this
/// box the structure has an infinite size, and the compiler stops.
nonisolated struct Indirect<Value: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    private nonisolated final class Storage: Sendable {
        let value: Value
        init(_ value: Value) { self.value = value }
    }

    private let storage: Storage

    var value: Value { storage.value }

    init(_ value: Value) { storage = Storage(value) }

    init(from decoder: any Decoder) throws {
        storage = Storage(try Value(from: decoder))
    }

    func encode(to encoder: any Encoder) throws {
        try value.encode(to: encoder)
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.value == rhs.value }

    func hash(into hasher: inout Hasher) { hasher.combine(value) }
}

// MARK: - Coding

extension JSONDecoder {
    /// The decoder for the format of Mastodon. The keys use lowercase words
    /// with an underscore between them. The API sends a date in three
    /// different formats, and this decoder reads all three.
    nonisolated static let mastodon: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            guard let date = Date.parseMastodonTimestamp(raw) else {
                throw DecodingError.dataCorruptedError(
                    in: try decoder.singleValueContainer(),
                    debugDescription: "Unrecognised timestamp \"\(raw)\""
                )
            }
            return date
        }
        return decoder
    }()
}

extension Date {
    /// Mastodon sends most dates as `2025-06-12T18:04:22.000Z`. Some forks
    /// send `2025-06-12T18:04:22Z`. The `last_status_at` field is only
    /// `2025-06-12`.
    ///
    /// The three format objects do not change, and they are `Sendable`. A
    /// `DateFormatter` object is different. Thus more than one actor can use
    /// these three objects.
    ///
    /// The function is `nonisolated`, because the decode operation runs off the
    /// main actor. The module makes `MainActor` the default. Without
    /// `nonisolated` the closure must change to the main actor. In the Swift 6
    /// language mode the compiler stops.
    nonisolated fileprivate static func parseMastodonTimestamp(_ string: String) -> Date? {
        if let date = try? fractional.parse(string) { return date }
        if let date = try? whole.parse(string) { return date }
        if let date = try? dateOnly.parse(string) { return date }
        return nil
    }

    nonisolated private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    nonisolated private static let whole = Date.ISO8601FormatStyle()
    nonisolated private static let dateOnly = Date.ISO8601FormatStyle().year().month().day()
}

private extension String {
    /// `follow_request` gives `followRequest`.
    nonisolated var camelCased: String {
        let parts = split(separator: "_")
        guard let first = parts.first else { return self }
        return parts.dropFirst().reduce(String(first)) { $0 + $1.capitalized }
    }
}
