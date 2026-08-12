//
//  RichText.swift
//  Pachyderm
//

import SwiftUI

/// Shows the text of a post. The text has styles and custom emoji.
///
/// The view makes one `Text` value from all the parts. Thus the text goes to the
/// next line, the user can select it, it changes size with Dynamic Type, and the
/// links accept a touch. The earlier view used a `UILabel` object, and none of
/// these functions operated. That view also gave no size. Thus it had a height
/// of zero in a `LazyVStack` view.
struct RichText: View {
    private let content: RichContent
    private let emoji: [Mastodon.Emoji]

    @State private var emojiImages: [String: Image] = [:]
    @ScaledMetric(relativeTo: .body) private var emojiHeight: CGFloat = 17
    @Environment(\.displayScale) private var displayScale

    init(content: RichContent, emoji: [Mastodon.Emoji]? = nil) {
        self.content = content
        self.emoji = emoji ?? []
    }

    /// Reads the HTML of the post, or takes the result from the cache.
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

    /// A sum of `Text` values. Only this construction puts an image in a line
    /// of text that goes to the next line.
    private var composed: Text {
        content.runs.reduce(Text(verbatim: "")) { result, run in
            switch run {
            case .text(let attributed):
                return result + Text(attributed)
            case .emoji(let shortcode):
                if let image = emojiImages[shortcode] {
                    return result + Text(image).baselineOffset(-1)
                }
                // Show the shortcode until the image arrives. Do not show an
                // empty space.
                return result + Text(verbatim: ":\(shortcode):")
            }
        }
    }

    // MARK: - Emoji

    /// Only the shortcodes in this post. Thus a server with 3000 custom emoji
    /// does not cause 3000 downloads.
    private var usedShortcodes: [String] {
        var seen = Set<String>()
        return content.runs.compactMap { run in
            guard case .emoji(let shortcode) = run, seen.insert(shortcode).inserted else { return nil }
            return shortcode
        }
    }

    private var emojiTaskID: String {
        "\(Int(emojiHeight))|\(usedShortcodes.joined(separator: ","))"
    }

    private func loadEmoji() async {
        let wanted = usedShortcodes
        guard !wanted.isEmpty else { return }

        let urls = Dictionary(
            emoji.filter { wanted.contains($0.shortcode) }
                .compactMap { item in item.imageURL.map { (item.shortcode, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        let height = emojiHeight

        for (shortcode, url) in urls where emojiImages[shortcode] == nil {
            guard let loaded = await ImageLoader.shared.image(
                for: url,
                maxPixelSize: Int((height * 2 * displayScale).rounded(.up))
            ) else { continue }
            guard !Task.isCancelled else { return }
            emojiImages[shortcode] = Image(uiImage: loaded.scaled(toHeight: height))
        }
    }
}

private extension UIImage {
    /// Sets a new scale value on the image. The image then has a height of
    /// `height` points. The pixels do not change.
    func scaled(toHeight height: CGFloat) -> UIImage {
        guard size.height > 0, let cgImage else { return self }
        let pixelHeight = CGFloat(cgImage.height)
        return UIImage(cgImage: cgImage, scale: pixelHeight / height, orientation: imageOrientation)
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
