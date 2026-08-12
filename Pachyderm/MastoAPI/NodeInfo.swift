//
//  NodeInfo.swift
//  Pachyderm
//
//  Created by Hariz Shirazi on 2026-08-11.
//

import Foundation

// MARK: - Discovery document

/// `/.well-known/nodeinfo` gives a list of links to the real documents.
///
/// This document is not part of `/api`. Thus the app gets it with
/// `MastodonHTTP.getPublic`.
nonisolated struct NodeInfoIndex: Decodable, Sendable {
    var links: [Link] = []

    nonisolated struct Link: Decodable, Sendable {
        /// Example: `http://nodeinfo.diaspora.software/ns/schema/2.1`.
        var rel: String?
        var href: String?

        /// The schema version at the end of `rel`. It selects the newest link.
        var schemaVersion: SoftwareVersion? {
            guard let rel, let slash = rel.lastIndex(of: "/") else { return nil }
            return SoftwareVersion(String(rel[rel.index(after: slash)...]))
        }
    }

    /// The link with the highest schema version. Version 2.0 and version 2.1
    /// differ only in fields that this app makes optional. Thus the highest
    /// version is always safe.
    var preferredHref: URL? {
        let usable = links.compactMap { link -> (SoftwareVersion, URL)? in
            guard let href = link.href, let url = URL(string: href) else { return nil }
            return (link.schemaVersion ?? .assumeAvailable, url)
        }
        return usable.max { $0.0 < $1.0 }?.1
    }
}

// MARK: - NodeInfo

/// The description that a server gives of itself. All fediverse software uses
/// this format. Thus this document is the primary source for the software
/// name. `/api/v1/instance` is the second source.
nonisolated struct NodeInfo: Decodable, Hashable, Sendable {
    /// The version of the NodeInfo schema. It is not the server version.
    var version: String?
    var software: Software?
    var protocols: [String]?
    var openRegistrations: Bool?
    var usage: Usage?
    var metadata: Metadata?

    nonisolated struct Software: Decodable, Hashable, Sendable {
        /// Usually lowercase: `mastodon`, `akkoma`, `gotosocial`.
        var name: String?
        /// A free format. It is near to semver, but not equal to it. Examples:
        /// `4.7.0-nightly.2026-08-10`, `0.22.1+git-fdff42b` and
        /// `3.20.0-1607-gd78d3e4f-akko-wtf`.
        var version: String?
        var homepage: String?
        var repository: String?
    }

    nonisolated struct Usage: Decodable, Hashable, Sendable {
        var localPosts: Int?
        var localComments: Int?
        var users: Users?

        nonisolated struct Users: Decodable, Hashable, Sendable {
            var total: Int?
            var activeMonth: Int?
            var activeHalfyear: Int?
        }
    }

    /// The NodeInfo schema does not specify the `metadata` object. Each
    /// software puts different data in it, and sometimes an unexpected type.
    /// Thus the initializer decodes each field separately. It removes a field
    /// with a wrong type, and it keeps the remainder of the document.
    nonisolated struct Metadata: Decodable, Hashable, Sendable {
        var nodeName: String?
        var nodeDescription: String?
        /// Pleroma and Akkoma give their extensions here.
        var features: [String]?
        var postFormats: [String]?

        private enum CodingKeys: String, CodingKey {
            case nodeName, nodeDescription, features, postFormats
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            nodeName = try? container.decodeIfPresent(String.self, forKey: .nodeName)
            nodeDescription = try? container.decodeIfPresent(String.self, forKey: .nodeDescription)
            features = try? container.decodeIfPresent([String].self, forKey: .features)
            postFormats = try? container.decodeIfPresent([String].self, forKey: .postFormats)
        }
    }
}
