//
//  APICapabilities.swift
//  Pachyderm
//
//  Created by Hariz Shirazi on 2026-08-11.
//

// Instance capability more or less ported from Feditext.

import Foundation

// MARK: - Version

/// A version number with tolerant parsing rules.
nonisolated struct SoftwareVersion: Hashable, Sendable, Comparable, Codable,
                                    CustomStringConvertible, ExpressibleByStringLiteral {
    var major: Int
    var minor: Int
    var patch: Int
    var prerelease: [String] = []
    var build: String?

    /// Use this value when all versions of the software have the feature.
    static let assumeAvailable = SoftwareVersion(major: 0, minor: 0, patch: 0)

    init(major: Int, minor: Int = 0, patch: Int = 0, prerelease: [String] = [], build: String? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
        self.build = build
    }

    init?(_ string: String) {
        var text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let space = text.firstIndex(of: " ") { text = String(text[..<space]) }
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
        guard !text.isEmpty else { return nil }

        if let plus = text.firstIndex(of: "+") {
            build = String(text[text.index(after: plus)...])
            text = String(text[..<plus])
        }
        if let dash = text.firstIndex(of: "-") {
            prerelease = String(text[text.index(after: dash)...])
                .split(separator: ".")
                .map(String.init)
            text = String(text[..<dash])
        }

        let core = text.split(separator: ".", omittingEmptySubsequences: false).map(Self.leadingInt)
        guard let major = core.first, let major else { return nil }
        self.major = major
        minor = core.count > 1 ? (core[1] ?? 0) : 0
        patch = core.count > 2 ? (core[2] ?? 0) : 0
    }
    
    private static func leadingInt(_ component: some StringProtocol) -> Int? {
        Int(component.prefix { $0.isNumber })
    }

    init(stringLiteral value: StringLiteralType) {
        // The literals in this app are the only input. A bad literal is a
        // defect in this code. It is not bad data from a server.
        self = SoftwareVersion(value) ?? .assumeAvailable
    }

    // MARK: Coding
    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = SoftwareVersion(raw) else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Unrecognised version \"\(raw)\""
            )
        }
        self = parsed
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    // MARK: Comparable

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }

        // Semver rule 11.3: a prerelease version comes before its release.
        if lhs.prerelease.isEmpty || rhs.prerelease.isEmpty {
            return !lhs.prerelease.isEmpty && rhs.prerelease.isEmpty
        }
        for (left, right) in zip(lhs.prerelease, rhs.prerelease) where left != right {
            switch (Int(left), Int(right)) {
            case let (l?, r?): return l < r
            case (_?, nil): return true      // A number has a lower rank than a word.
            case (nil, _?): return false
            case (nil, nil): return left < right
            }
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }

    // MARK: Description

    /// The complete version. Example: `4.4.0-alpha.5+glitch`.
    var description: String {
        var text = shortDescription
        if !prerelease.isEmpty { text += "-" + prerelease.joined(separator: ".") }
        if let build { text += "+" + build }
        return text
    }

    /// Only the three numbers. Show this text in the user interface.
    var shortDescription: String { "\(major).\(minor).\(patch)" }
}

// MARK: - Flavor

/// The server software.
nonisolated enum APIFlavor: String, Codable, Hashable, Sendable, CaseIterable {
    case mastodon, glitch, chuckya, hometown, pleroma, akkoma, gotosocial, iceshrimp,sharkey, firefish, calckey, misskey, friendica, pixelfed, hollo, mitra, takahe

    init?(softwareName: String) {
        let name = softwareName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let exact = APIFlavor(rawValue: name) {
            self = exact
            return
        }
        switch name {
        case "glitch-soc", "glitchsoc", "mastodon-glitch": self = .glitch
        case "iceshrimp.net", "iceshrimp-net": self = .iceshrimp
        case "takahē": self = .takahe
        default: return nil
        }
    }

    var displayName: String {
        switch self {
        case .mastodon: "Mastodon"
        case .glitch: "glitch-soc"
        case .chuckya: "Chuckya"
        case .hometown: "Hometown"
        case .pleroma: "Pleroma"
        case .akkoma: "Akkoma"
        case .gotosocial: "GoToSocial"
        case .iceshrimp: "Iceshrimp"
        case .sharkey: "Sharkey"
        case .firefish: "Firefish"
        case .calckey: "Calckey"
        case .misskey: "Misskey"
        case .friendica: "Friendica"
        case .pixelfed: "Pixelfed"
        case .hollo: "Hollo"
        case .mitra: "Mitra"
        case .takahe: "Takahē"
        }
    }

    /// These forks use the version numbers of Mastodon. A minimum Mastodon
    /// version applies also to them.
    var isMastodonFork: Bool {
        switch self {
        case .mastodon, .glitch, .chuckya, .hometown: true
        default: false
        }
    }
}

// MARK: - Features

/// A server extension. A version number does not show these extensions.
///
/// Pleroma and Akkoma list their extensions in `nodeinfo.metadata.features`.
/// This list is more accurate than a version number, because an administrator
/// can disable a single feature.
nonisolated enum APIFeature: String, Codable, Hashable, Sendable, CaseIterable {
    case emojiReactions
    case quotePosts
    case editPosts
    case translation
    case bubbleTimeline
    case localOnlyPosts
    case polls
    case streaming
    case notificationTypeFilters
    case profileDirectory

    /// Changes the strings from the forks into the cases above. The
    /// initializer ignores an unknown string. An unknown extension is not an
    /// error.
    init?(forkFeature raw: String) {
        switch raw.lowercased() {
        case "pleroma_emoji_reactions", "custom_emoji_reactions", "emoji_reactions":
            self = .emojiReactions
        case "quote_posting", "quote_posts":
            self = .quotePosts
        case "editing", "status_editing":
            self = .editPosts
        case "akkoma:machine_translation", "translation":
            self = .translation
        case "bubble_timeline":
            self = .bubbleTimeline
        case "local_only", "local_only_posts":
            self = .localOnlyPosts
        case "polls":
            self = .polls
        case "mastodon_api_streaming", "pleroma:api/v1/streaming":
            self = .streaming
        case "pleroma:api/v1/notifications:include_types_filter":
            self = .notificationTypeFilters
        case "profile_directory":
            self = .profileDirectory
        default:
            return nil
        }
    }
}

// MARK: - Capabilities

/// The abilities of one instance. The structure is small and easy to copy.
///
/// It is `Codable`. Thus the app can keep it between two launches and show
/// the correct controls in the first frame. It does not have to wait for two
/// requests.
nonisolated struct APICapabilities: Codable, Hashable, Sendable {
    /// The `software.name` value from the server. The app keeps this text also
    /// when it does not know the name. The text helps the user and the log.
    var softwareName: String?
    var flavor: APIFlavor?
    var version: SoftwareVersion?
    var features: Set<APIFeature> = []

    /// The value before the app asks the server. Nothing is known.
    static let unknown = APICapabilities()

    init(
        softwareName: String? = nil,
        flavor: APIFlavor? = nil,
        version: SoftwareVersion? = nil,
        features: Set<APIFeature> = []
    ) {
        self.softwareName = softwareName
        self.flavor = flavor
        self.version = version
        self.features = features
    }

    /// The usual method. NodeInfo gives the name and the version of the
    /// software.
    init(nodeInfo: NodeInfo) {
        let raw = nodeInfo.software?.version ?? ""
        softwareName = nodeInfo.software?.name
        flavor = nodeInfo.software?.name.flatMap(APIFlavor.init(softwareName:))
        version = SoftwareVersion(raw)
        features = Set((nodeInfo.metadata?.features ?? []).compactMap(APIFeature.init(forkFeature:)))
        flavor = Self.refineMastodonFork(flavor, versionString: raw)
    }

    /// The alternative method for a server without a NodeInfo document.
    ///
    /// Only two formats are clear here: the Mastodon forks and the Pleroma
    /// family. A version such as `0.22.1+git-…` can come from any software.
    /// The app then sets the version and keeps the flavor empty. A wrong
    /// value is worse than no value.
    init(instance: Mastodon.Instance) {
        let raw = instance.version ?? ""

        // Pleroma and Akkoma report the version `2.7.2`. The correct data is
        // in the parentheses: `2.7.2 (compatible; Akkoma 3.20.0-1607-gd78d3)`.
        if let inner = Self.compatibilityParenthetical(in: raw) {
            let parts = inner.split(separator: " ", maxSplits: 1).map(String.init)
            softwareName = parts.first
            flavor = parts.first.flatMap(APIFlavor.init(softwareName:))
            version = parts.count > 1 ? SoftwareVersion(parts[1]) : nil
        } else {
            version = SoftwareVersion(raw)
            flavor = Self.refineMastodonFork(nil, versionString: raw)
            softwareName = flavor?.rawValue
        }
    }

    /// Glitch-soc, Chuckya and Hometown all report the name `mastodon`. The
    /// build metadata identifies them. Examples:
    /// `4.4.0-alpha.5+glitch+urusai+sakura` and `4.7.0-beta.1+chuckya`.
    ///
    /// The function tests for Chuckya first. Chuckya comes from glitch-soc.
    /// Thus a build with both names is a Chuckya build.
    private static func refineMastodonFork(_ flavor: APIFlavor?, versionString: String) -> APIFlavor? {
        guard flavor == nil || flavor?.isMastodonFork == true else { return flavor }
        let raw = versionString.lowercased()
        if raw.contains("chuckya") { return .chuckya }
        if raw.contains("glitch") { return .glitch }
        if raw.contains("hometown") { return .hometown }
        return flavor
    }

    private static func compatibilityParenthetical(in version: String) -> String? {
        guard let open = version.range(of: "(compatible;", options: .caseInsensitive) else { return nil }
        let rest = version[open.upperBound...]
        let inner = rest.prefix { $0 != ")" }
        let trimmed = inner.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// True when the app knows the software and the version. A `false` result
    /// from `satisfies(_:)` then has a meaning.
    var isDetected: Bool { flavor != nil && version != nil }

    /// A short text for a settings screen or a defect report. Example:
    /// `Akkoma 3.20.0`.
    var summary: String {
        let name = flavor?.displayName ?? softwareName
        return switch (name, version) {
        case let (name?, version?): "\(name) \(version.shortDescription)"
        case let (name?, nil): name
        case let (nil, version?): "Unknown server \(version.shortDescription)"
        case (nil, nil): "Unknown server"
        }
    }

    /// Copies the unknown values from `other`. The known values do not change.
    /// Thus `/api/v1/instance` can complete an incomplete NodeInfo result.
    func merging(_ other: APICapabilities) -> APICapabilities {
        APICapabilities(
            softwareName: softwareName ?? other.softwareName,
            flavor: flavor ?? other.flavor,
            version: version ?? other.version,
            features: features.union(other.features)
        )
    }

    /// Lets a call site read as `api.capabilities.satisfies(.statusEdits)`.
    func satisfies(_ requirements: APICapabilityRequirements) -> Bool {
        requirements.satisfiedBy(self)
    }
}

// MARK: - Requirements

/// The requirements of one feature. One condition is sufficient: a minimum
/// version for the flavor, or an extension in the list of the server.
///
///     static let statusEdits: APICapabilityRequirements =
///         .mastodonForks("3.5.0") | [.pleroma: "2.5.0"] | .features(.editPosts)
nonisolated struct APICapabilityRequirements: Hashable, Sendable, ExpressibleByDictionaryLiteral {
    /// Each flavor and the first version with the feature. `.assumeAvailable`
    /// means that all versions have the feature.
    var minimumVersions: [APIFlavor: SoftwareVersion]
    /// One extension in this set is sufficient.
    var requiredFeatures: Set<APIFeature>

    init(
        minimumVersions: [APIFlavor: SoftwareVersion] = [:],
        requiredFeatures: Set<APIFeature> = []
    ) {
        self.minimumVersions = minimumVersions
        self.requiredFeatures = requiredFeatures
    }

    init(dictionaryLiteral elements: (APIFlavor, SoftwareVersion)...) {
        minimumVersions = Dictionary(elements, uniquingKeysWith: min)
        requiredFeatures = []
    }

    /// Mastodon and the forks with the same version numbers.
    static func mastodonForks(_ version: SoftwareVersion) -> Self {
        Self(minimumVersions: Dictionary(
            uniqueKeysWithValues: APIFlavor.allCases.filter(\.isMastodonFork).map { ($0, version) }
        ))
    }

    static func features(_ features: APIFeature...) -> Self {
        Self(requiredFeatures: Set(features))
    }

    /// Makes a union. One side is sufficient. The operator keeps the lower
    /// minimum version, because a feature from version 3.5 is also in version
    /// 4.0.
    static func | (lhs: Self, rhs: Self) -> Self {
        Self(
            minimumVersions: lhs.minimumVersions.merging(rhs.minimumVersions, uniquingKeysWith: min),
            requiredFeatures: lhs.requiredFeatures.union(rhs.requiredFeatures)
        )
    }

    /// An unknown server does not satisfy a requirement. Use this function to
    /// offer an optional feature. Use `MastoAPI.supportsOrUnknown` when a
    /// hidden control is worse than an error from the server.
    func satisfiedBy(_ capabilities: APICapabilities) -> Bool {
        if !requiredFeatures.isEmpty, !requiredFeatures.isDisjoint(with: capabilities.features) {
            return true
        }
        guard let flavor = capabilities.flavor,
              let minimum = minimumVersions[flavor]
        else { return false }
        guard let version = capabilities.version else { return minimum == .assumeAvailable }
        return version >= minimum
    }
}

// MARK: - Catalog

/// The requirements that Pachyderm knows.
extension APICapabilityRequirements {
    /// `PUT /api/v1/statuses/:id`.
    static let statusEdits: Self =
        .mastodonForks("3.5.0")
        | [.pleroma: "2.5.0", .akkoma: .assumeAvailable, .gotosocial: "0.16.0", .hollo: .assumeAvailable]
        | .features(.editPosts)

    /// Emoji reactions on a status. Mastodon does not have them. GoToSocial
    /// also does not have them. Version 0.22.1 answers 404.
    ///
    /// The endpoint is different in each fork. Chuckya uses
    /// `POST /api/v1/statuses/:id/react/:emoji` and `/unreact/:emoji`. The
    /// Pleroma family uses
    /// `PUT /api/v1/pleroma/statuses/:id/reactions/:emoji`.
    static let emojiReactions: Self =
        [
            .chuckya: .assumeAvailable,
            .pleroma: "2.0.0",
            .akkoma: .assumeAvailable,
            .iceshrimp: .assumeAvailable,
            .sharkey: .assumeAvailable,
            .firefish: .assumeAvailable,
            .calckey: .assumeAvailable,
            .misskey: .assumeAvailable,
        ]
        | .features(.emojiReactions)

    /// Mastodon added quotes late. Version 4.6.5 sends the fields `quote`,
    /// `quote_approval` and `quotes_count`. Version 4.6 is the earliest
    /// version with a test result. An earlier version can also have quotes.
    static let quotePosts: Self =
        .mastodonForks("4.6.0")
        | [
            .pleroma: "2.6.0",
            .akkoma: .assumeAvailable,
            .iceshrimp: .assumeAvailable,
            .sharkey: .assumeAvailable,
            .firefish: .assumeAvailable,
            .hollo: .assumeAvailable,
        ]
        | .features(.quotePosts)

    /// The `local_only` field. It is a parameter of `POST /api/v1/statuses`.
    /// It is also a field of a status from the server.
    static let localOnlyPosts: Self =
        [
            .glitch: .assumeAvailable,
            .chuckya: .assumeAvailable,
            .hometown: .assumeAvailable,
            .akkoma: .assumeAvailable,
        ]
        | .features(.localOnlyPosts)

    /// `/api/v2/instance`. It replaces the v1 document that this app reads.
    static let instanceV2: Self =
        .mastodonForks("4.0.0")
        | [.gotosocial: "0.14.0", .iceshrimp: .assumeAvailable, .hollo: .assumeAvailable]

    /// `POST /api/v1/statuses/:id/translate`.
    static let translation: Self =
        .mastodonForks("4.0.0") | .features(.translation)

    /// `/api/v2/notifications`. The server puts the notifications in groups.
    static let groupedNotifications: Self = .mastodonForks("4.3.0")

    /// The bubble timeline of Akkoma. It shows posts from related instances.
    static let bubbleTimeline: Self =
        [.akkoma: .assumeAvailable] | .features(.bubbleTimeline)

    /// `/api/v1/conversations`. The Messages tab uses this endpoint.
    static let directConversations: Self =
        .mastodonForks("2.6.0")
        | [.pleroma: .assumeAvailable, .akkoma: .assumeAvailable, .gotosocial: .assumeAvailable]
}
