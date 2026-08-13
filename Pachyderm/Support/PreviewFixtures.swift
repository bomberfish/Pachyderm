//
//  PreviewFixtures.swift
//  Pachyderm
//

import Foundation
import SwiftUI

// This file is not in a `#if DEBUG` block. That decision is intentional. The
// `#Preview` macro expands in each configuration. Thus a debug-only fixture
// stops the Release build. The cost is some kilobytes of JSON in the shipping
// binary.

/// Example values for a `#Preview` macro.
///
/// The function decodes each value from JSON. It does not use a memberwise
/// initializer. Thus each value also tests the model against the wire format.
private func fixture<T: Decodable>(_ json: String) -> T {
    do {
        return try JSONDecoder.mastodon.decode(T.self, from: Data(json.utf8))
    } catch {
        // This code runs only in a preview. A stop here shows that a fixture
        // and its model are different.
        fatalError("Bad \(T.self) fixture: \(error)")
    }
}

private let accountJSON = """
{
  "id": "1",
  "username": "ellie",
  "acct": "ellie",
  "display_name": "Ellie :blobcat:",
  "note": "<p>Cat person. Swift, coffee, and trains.</p>",
  "url": "https://mastodon.example/@ellie",
  "avatar": "https://mastodon.example/avatars/1.png",
  "header": "https://mastodon.example/headers/1.png",
  "followers_count": 1284,
  "following_count": 317,
  "statuses_count": 4096,
  "locked": false,
  "bot": false,
  "created_at": "2019-03-14T00:00:00.000Z",
  "emojis": [
    {
      "shortcode": "blobcat",
      "url": "https://mastodon.example/emoji/blobcat.png",
      "static_url": "https://mastodon.example/emoji/blobcat.png",
      "visible_in_picker": true
    }
  ],
  "fields": [
    {
      "name": "Website",
      "value": "<a href=\\"https://example.com\\">example.com</a>",
      "verified_at": "2024-01-02T03:04:05.000Z"
    },
    { "name": "Pronouns", "value": "they/them" }
  ]
}
"""

private let otherAccountJSON = """
{
  "id": "2",
  "username": "boostbot",
  "acct": "boostbot@remote.example",
  "display_name": "Boost Bot",
  "url": "https://remote.example/@boostbot",
  "avatar": "https://remote.example/avatars/2.png",
  "bot": true,
  "followers_count": 12,
  "following_count": 0,
  "statuses_count": 99999
}
"""

private func statusJSON(
    id: String,
    account: String,
    content: String,
    extras: String = ""
) -> String {
    """
    {
      "id": "\(id)",
      "uri": "https://mastodon.example/users/ellie/statuses/\(id)",
      "url": "https://mastodon.example/@ellie/\(id)",
      "created_at": "2025-06-13T09:41:00.000Z",
      "content": "\(content)",
      "visibility": "public",
      "sensitive": false,
      "language": "en",
      "replies_count": 3,
      "reblogs_count": 12,
      "favourites_count": 48,
      "favourited": false,
      "reblogged": false,
      "bookmarked": false,
      "account": \(account)\(extras.isEmpty ? "" : ",\n  " + extras)
    }
    """
}

extension Mastodon.Account {
    static let preview: Self = fixture(accountJSON)
    static let previewOther: Self = fixture(otherAccountJSON)
}

extension Mastodon.Status {
    static let preview: Self = fixture(statusJSON(
        id: "100",
        account: accountJSON,
        content: "<p>Rewrote the timeline today. It <strong>scrolls</strong> now, which is more than it did this morning.</p>"
    ))

    /// A boost has two statuses. The outer status holds the account that made
    /// the boost. The inner status holds the content.
    static let previewBoost: Self = fixture("""
    {
      "id": "101",
      "created_at": "2025-06-13T10:02:00.000Z",
      "content": "",
      "visibility": "public",
      "replies_count": 0,
      "reblogs_count": 0,
      "favourites_count": 0,
      "account": \(otherAccountJSON),
      "reblog": \(statusJSON(
        id: "100",
        account: accountJSON,
        content: "<p>Rewrote the timeline today. It <strong>scrolls</strong> now.</p>"
      ))
    }
    """)

    static let previewSensitive: Self = fixture(statusJSON(
        id: "102",
        account: accountJSON,
        content: "<p>The spoiler is that there is no spoiler.</p>",
        extras: """
        "spoiler_text": "Season finale spoilers",
        "sensitive": true
        """
    ))
}

extension Mastodon.Notification {
    static let preview: Self = fixture("""
    {
      "id": "900",
      "type": "favourite",
      "created_at": "2025-06-13T10:15:00.000Z",
      "account": \(otherAccountJSON),
      "status": \(statusJSON(id: "100", account: accountJSON, content: "<p>Hello there.</p>"))
    }
    """)

    static let previewFollow: Self = fixture("""
    {
      "id": "901",
      "type": "follow_request",
      "created_at": "2025-06-13T10:20:00.000Z",
      "account": \(otherAccountJSON)
    }
    """)
}

extension View {
    /// Puts each value that a view of the app reads into the environment.
    func previewEnvironment() -> some View {
        let api = MastoAPI(credentials: MastodonCredentials(
            host: "mastodon.example",
            accessToken: "preview"
        ))
        return MastodonNavigationStack {
            self
        }
        .environment(api)
        .environment(ErrorPresenter())
        // A preview never calls `start()`, thus this center opens no socket.
        .environment(StreamingCenter(api: api))
    }
}
