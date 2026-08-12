//
//  RichText.swift
//  Pachyderm
//

import SwiftUI

/// Shows the text of a post. The text has styles and custom emoji.
///
/// A post with no custom emoji becomes one `Text` value. A post with emoji
/// becomes a sum of `Text` values, because only such a sum puts an image in a
/// line of text that goes to the next line. The text thus goes to the next
/// line, the user can select it, it changes size with Dynamic Type, and the
/// links accept a touch. The earlier view used a `UILabel` object, and none of
/// these functions operated. That view also gave no size. Thus it had a height
/// of zero in a `LazyVStack` view.
struct RichText: View {
    private let content: RichContent
    private let emoji: [Mastodon.Emoji]

    /// Grows by one when an image arrives. The images live in a shared cache,
    /// thus only this value tells SwiftUI to make the body again.
    @State private var revision = 0
    @ScaledMetric(relativeTo: .body) private var emojiHeight: CGFloat = 17
    @Environment(\.displayScale) private var displayScale

    init(content: RichContent, emoji: [Mastodon.Emoji]? = nil) {
        self.content = content
        self.emoji = emoji ?? []
    }

    /// Reads the HTML of the post, or takes the result from the cache.
    /// `PagedListModel` fills the cache for a whole page, thus a cell in a list
    /// finds the result here.
    init(html: String, emoji: [Mastodon.Emoji]? = nil) {
        self.init(
            content: RichContentCache.shared.content(html: html, emoji: emoji),
            emoji: emoji
        )
    }

    var body: some View {
        composed
            .accessibilityLabel(content.plainText)
            .task(id: emojiTaskID) { await loadEmoji() }
    }

    private var composed: Text {
        // The usual case: one value, with no work on the runs and no sum.
        guard content.hasEmoji else { return Text(content.text) }

        // The read of `revision` keeps the body dependent on the load
        // operation. The images themselves come from a shared cache, and
        // SwiftUI does not observe that cache.
        _ = revision

        let urls = emojiURLs
        return content.segments.reduce(Text(verbatim: "")) { result, segment in
            switch segment {
            case .text(let attributed):
                return result + Text(attributed)
            case .emoji(let shortcode):
                if let url = urls[shortcode],
                   let image = EmojiImageCache.shared.image(for: url, height: emojiHeight) {
                    return result + Text(image).baselineOffset(-1)
                }
                // Show the shortcode until the image arrives. Do not show an
                // empty space.
                return result + Text(verbatim: ":\(shortcode):")
            }
        }
    }

    // MARK: - Emoji

    /// The address of each emoji in this post. A server can hold 3000 custom
    /// emoji; only the ones in the text need an image.
    private var emojiURLs: [String: URL] {
        guard content.hasEmoji else { return [:] }

        let wanted = Set(content.shortcodes)
        return Dictionary(
            emoji.lazy
                .filter { wanted.contains($0.shortcode) }
                .compactMap { item in item.imageURL.map { (item.shortcode, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private var emojiTaskID: String {
        "\(Int(emojiHeight))|\(content.shortcodes.joined(separator: ","))"
    }

    private func loadEmoji() async {
        let urls = emojiURLs
        guard !urls.isEmpty else { return }

        let height = emojiHeight
        let scale = displayScale

        for url in urls.values where EmojiImageCache.shared.image(for: url, height: height) == nil {
            let arrived = await EmojiImageCache.shared.load(url: url, height: height, scale: scale)
            guard !Task.isCancelled else { return }
            if arrived { revision &+= 1 }
        }
    }
}

#Preview("Rich text") {
    let html = """
    <p>Hello <strong>world</strong>, this is <em>emphasised</em> and \
    <del>struck out</del> with <code>inline code</code>.</p>\
    <p>A link: <a href="https://joinmastodon.org/about/very/long/path">\
    <span class="invisible">https://</span>\
    <span class="ellipsis">joinmastodon.org/about</span>\
    <span class="invisible">/very/long/path</span></a></p>\
    <p>Entities: caf&#233; &amp; cr&egrave;me &mdash; 5 &lt; 6</p>\
    <p>Custom emoji: :blobcat: inline.</p>
    """

    ScrollView {
        RichText(
            html: html,
            emoji: [Mastodon.Emoji(shortcode: "blobcat", url: nil, staticUrl: nil, visibleInPicker: true)]
        )
        .padding()
    }
}
