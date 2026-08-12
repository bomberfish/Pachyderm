//
//  MastodonHTML.swift
//  Pachyderm
//

import Foundation

/// The text of a post with its styles and its custom emoji.
///
/// A custom emoji is one placeholder character inside `text`. That character
/// holds the shortcode in the `customEmoji` attribute. Thus the whole post is
/// one `AttributedString` value. A view can show it in one step, a screen
/// reader gets `plainText`, and an editor can change it and keep the emoji in
/// place.
nonisolated struct RichContent: Hashable, Sendable {
    /// The character that stands for a custom emoji. Unicode calls it OBJECT
    /// REPLACEMENT CHARACTER. It is the character that a text engine uses for
    /// content from outside the text.
    static let emojiPlaceholder: Character = "\u{FFFC}"

    var text: AttributedString
    /// The text with no style. A custom emoji keeps its `:shortcode:` form.
    /// Use it for a screen reader, for a preview and for a copy operation.
    var plainText: String
    /// Each shortcode in the text, in order of first appearance, with no
    /// repeat.
    var shortcodes: [String]

    /// True when the text holds a custom emoji. A view reads this value first:
    /// a post with no emoji needs no work with the runs.
    var hasEmoji: Bool { !shortcodes.isEmpty }

    var isEmpty: Bool { plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    static let empty = RichContent(text: AttributedString(), plainText: "", shortcodes: [])
}

// MARK: - Segments

nonisolated extension RichContent {
    /// One piece of the text for a view.
    enum Segment: Hashable, Sendable {
        case text(AttributedString)
        /// A custom emoji. The value is the shortcode without the two colons.
        case emoji(String)
    }

    /// Divides the text at each custom emoji.
    ///
    /// `AttributedString.Runs` gives the ranges of one attribute directly,
    /// thus the parser needs no second copy of the text. Call this only when
    /// `hasEmoji` is true.
    var segments: [Segment] {
        var result: [Segment] = []
        for (shortcode, range) in text.runs[\.customEmoji] {
            if let shortcode {
                result.append(.emoji(shortcode))
            } else {
                result.append(.text(AttributedString(text[range])))
            }
        }
        return result
    }
}

// MARK: - Parser

nonisolated extension RichContent {
    /// Reads the small group of HTML tags that Mastodon sends.
    ///
    /// This function replaces
    /// `NSAttributedString(data:options:[.documentType: .html])`. That
    /// initializer uses WebKit, thus it must run on the main thread. The
    /// earlier code called it from a background task. Such a call has no
    /// defined result. When it operates, it also stops the scroll movement.
    ///
    /// - Parameter knownEmoji: The shortcodes for this post from the server.
    ///   The function makes a placeholder for only these shortcodes. Other
    ///   text between two colons does not change.
    static func parse(html: String, knownEmoji: Set<String> = []) -> RichContent {
        guard !html.isEmpty else { return .empty }
        var parser = Parser(html: html, knownEmoji: knownEmoji)
        return parser.parse()
    }

    private nonisolated struct Parser {
        /// The reader walks over UTF-8 bytes, not over characters. A step with
        /// `String.Index` needs grapheme work at each position. The markup
        /// characters `<`, `>`, `&` and `/` are all ASCII, and UTF-8 puts no
        /// ASCII byte inside a longer character. Thus a byte walk finds the
        /// same positions and never divides a character.
        private let bytes: [UInt8]
        private let knownEmoji: Set<String>

        private var text = AttributedString()
        private var plain = ""
        private var shortcodes: [String] = []
        private var seenShortcodes = Set<String>()

        /// Text that waits for its attributes. The parser holds it until the
        /// style changes. Thus `<p>one <b>two</b> three</p>` needs three
        /// `AttributedString` values, not one for each piece between two tags.
        private var pending = ""
        private var pendingStyle = Style()

        // Each style has a counter, not a flag. In
        // `<strong><strong>x</strong>y</strong>` the letter `y` must stay bold.
        private var bold = 0
        private var italic = 0
        private var strikethrough = 0
        private var code = 0
        private var links: [URL] = []
        private var spans: [SpanKind] = []
        private var invisibleDepth = 0

        private enum SpanKind { case plain, invisible, ellipsis }

        /// The style of one piece of text. `AttributeContainer` needs an
        /// allocation for each value, thus the parser compares this small
        /// value instead and makes a container only at the end of a piece.
        private struct Style: Equatable {
            var intent: InlinePresentationIntent = []
            var link: URL?
        }

        init(html: String, knownEmoji: Set<String>) {
            self.bytes = Array(html.utf8)
            self.knownEmoji = knownEmoji
        }

        mutating func parse() -> RichContent {
            let count = bytes.count
            var index = 0
            var textStart = 0

            while index < count {
                guard bytes[index] == Self.lessThan else {
                    index += 1
                    continue
                }
                append(textFrom: textStart, to: index)
                guard let close = indexOfTagEnd(after: index) else {
                    // The tag has no end character. Use the remainder as text.
                    textStart = index
                    break
                }
                handle(tagFrom: index + 1, to: close)
                index = close + 1
                textStart = index
            }
            append(textFrom: textStart, to: count)

            flushPending()
            trimTrailingWhitespace()
            return RichContent(
                text: text,
                plainText: plain.trimmingCharacters(in: .whitespacesAndNewlines),
                shortcodes: shortcodes
            )
        }

        private func indexOfTagEnd(after start: Int) -> Int? {
            var cursor = start + 1
            while cursor < bytes.count {
                if bytes[cursor] == Self.greaterThan { return cursor }
                cursor += 1
            }
            return nil
        }

        // MARK: Tags

        private mutating func handle(tagFrom start: Int, to end: Int) {
            var cursor = start
            while cursor < end, Self.isTagSpace(bytes[cursor]) { cursor += 1 }
            guard cursor < end else { return }
            // `<!-- a comment -->` and `<!DOCTYPE …>` hold no text.
            guard bytes[cursor] != Self.exclamation else { return }

            let isClosing = bytes[cursor] == Self.slash
            while cursor < end, bytes[cursor] == Self.slash { cursor += 1 }

            let nameStart = cursor
            while cursor < end, !Self.isNameEnd(bytes[cursor]) { cursor += 1 }
            let name = Self.lowercasedName(bytes[nameStart..<cursor])

            switch name {
            case "br":
                appendRaw("\n")
            case "p", "div", "blockquote", "li", "h1", "h2", "h3", "h4", "h5", "h6":
                // The end of a block becomes an empty line. The
                // `trimTrailingWhitespace` function removes the extra lines.
                if isClosing { appendRaw("\n\n") }
            case "strong", "b":
                bold += isClosing ? -1 : 1
            case "em", "i":
                italic += isClosing ? -1 : 1
            case "del", "s", "strike":
                strikethrough += isClosing ? -1 : 1
            case "code", "pre":
                code += isClosing ? -1 : 1
            case "a":
                if isClosing {
                    if !links.isEmpty { links.removeLast() }
                } else {
                    // Only these two tags need their attributes. The tag of a
                    // paragraph or of a style thus needs no text value at all.
                    openLink(body: Self.string(bytes[start..<end]))
                }
            case "span":
                handleSpan(from: start, to: end, isClosing: isClosing)
            default:
                break
            }

            bold = max(0, bold)
            italic = max(0, italic)
            strikethrough = max(0, strikethrough)
            code = max(0, code)
        }

        private mutating func openLink(body: String) {
            if let href = Self.attribute("href", in: body),
               let url = URL(string: Self.decodeEntities(href)) {
                links.append(url)
            } else {
                // Add an item also for a bad `href` value. The stack must keep
                // one item for each `<a>` tag.
                links.append(Self.blankLink)
            }
        }

        /// Mastodon makes a long link shorter with three `span` elements:
        /// `<span class="invisible">https://</span><span class="ellipsis">example.com/a</span><span class="invisible">/long/path</span>`
        /// The parser removes the hidden parts. It puts three dots at the end
        /// of the short text.
        private mutating func handleSpan(from start: Int, to end: Int, isClosing: Bool) {
            if isClosing {
                guard let kind = spans.popLast() else { return }
                switch kind {
                case .invisible: invisibleDepth -= 1
                case .ellipsis: appendRaw("…")
                case .plain: break
                }
                invisibleDepth = max(0, invisibleDepth)
                return
            }

            let classes = Self.attribute("class", in: Self.string(bytes[start..<end])) ?? ""
            if classes.contains("invisible") {
                spans.append(.invisible)
                invisibleDepth += 1
            } else if classes.contains("ellipsis") {
                spans.append(.ellipsis)
            } else {
                spans.append(.plain)
            }
        }

        // MARK: Text

        private mutating func append(textFrom start: Int, to end: Int) {
            guard start < end else { return }
            let slice = bytes[start..<end]
            let value = Self.string(slice)
            // The search for `&` reads bytes. The alternative reads characters
            // of a value that holds no entity in almost every case.
            appendRaw(slice.contains(Self.ampersand) ? Self.decodeEntities(value) : value)
        }

        private mutating func appendRaw(_ value: String) {
            guard !value.isEmpty, invisibleDepth == 0 else { return }

            guard !knownEmoji.isEmpty else {
                appendStyled(value)
                return
            }
            for piece in Self.split(value, shortcodes: knownEmoji) {
                switch piece {
                case .text(let text):
                    appendStyled(text)
                case .emoji(let shortcode):
                    appendEmoji(shortcode)
                }
            }
        }

        private mutating func appendStyled(_ value: String) {
            guard !value.isEmpty else { return }

            let style = currentStyle
            if pending.isEmpty {
                pendingStyle = style
            } else if style != pendingStyle {
                flushPending()
                pendingStyle = style
            }
            pending += value
            plain += value
        }

        private mutating func appendEmoji(_ shortcode: String) {
            flushPending()

            var piece = AttributedString(String(RichContent.emojiPlaceholder))
            // The placeholder keeps the style around it. An emoji inside a
            // link thus opens that link, and text written next to the emoji
            // later keeps the style of its neighbour.
            piece.mergeAttributes(Self.container(for: currentStyle))
            piece.customEmoji = shortcode
            text.append(piece)

            plain += ":\(shortcode):"
            if seenShortcodes.insert(shortcode).inserted { shortcodes.append(shortcode) }
        }

        private var currentStyle: Style {
            var intent: InlinePresentationIntent = []
            if bold > 0 { intent.insert(.stronglyEmphasized) }
            if italic > 0 { intent.insert(.emphasized) }
            if strikethrough > 0 { intent.insert(.strikethrough) }
            if code > 0 { intent.insert(.code) }

            let link = links.last.flatMap { $0.scheme == "about" ? nil : $0 }
            return Style(intent: intent, link: link)
        }

        private static func container(for style: Style) -> AttributeContainer {
            var container = AttributeContainer()
            if !style.intent.isEmpty { container.inlinePresentationIntent = style.intent }
            if let link = style.link { container.link = link }
            return container
        }

        private mutating func flushPending() {
            guard !pending.isEmpty else { return }
            var piece = AttributedString(pending)
            piece.mergeAttributes(Self.container(for: pendingStyle))
            text.append(piece)
            pending = ""
        }

        /// Removes the empty line at the end. Each `</p>` tag makes one.
        ///
        /// The walk goes backwards over the characters and stops at the first
        /// character that is not whitespace. The placeholder of an emoji is
        /// not whitespace, thus the walk stops there.
        private mutating func trimTrailingWhitespace() {
            let characters = text.characters
            var end = characters.endIndex
            while end > characters.startIndex {
                let previous = characters.index(before: end)
                guard characters[previous].isWhitespace else { break }
                end = previous
            }
            guard end < characters.endIndex else { return }
            text.removeSubrange(end..<text.endIndex)
        }

        // MARK: Static helpers

        private static let lessThan = UInt8(ascii: "<")
        private static let greaterThan = UInt8(ascii: ">")
        private static let ampersand = UInt8(ascii: "&")
        private static let slash = UInt8(ascii: "/")
        private static let exclamation = UInt8(ascii: "!")
        private static let blankLink = URL(string: "about:blank")!

        /// A space at the start of a tag. The name of a tag ends at one of
        /// these, at a slash, or at the end of the tag.
        private static func isTagSpace(_ byte: UInt8) -> Bool {
            byte == 0x20 || byte == 0x09
        }

        private static func isNameEnd(_ byte: UInt8) -> Bool {
            byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D || byte == slash
        }

        private static func string(_ slice: ArraySlice<UInt8>) -> String {
            String(decoding: slice, as: UTF8.self)
        }

        /// The name of a tag with no capital letter. HTML compares a tag name
        /// with the rules of ASCII, thus this function changes only A to Z.
        private static func lowercasedName(_ slice: ArraySlice<UInt8>) -> String {
            var name = [UInt8]()
            name.reserveCapacity(slice.count)
            for byte in slice {
                name.append(byte >= 0x41 && byte <= 0x5A ? byte + 0x20 : byte)
            }
            return String(decoding: name, as: UTF8.self)
        }

        private enum Piece {
            case text(String)
            case emoji(String)
        }

        /// Divides `Hello :blobcat: there` into text parts and emoji parts.
        private static func split(_ text: String, shortcodes: Set<String>) -> [Piece] {
            guard text.contains(":") else { return [.text(text)] }

            var pieces: [Piece] = []
            var buffer = ""
            var index = text.startIndex

            while index < text.endIndex {
                guard text[index] == ":" else {
                    buffer.append(text[index])
                    index = text.index(after: index)
                    continue
                }
                let afterColon = text.index(after: index)
                guard let end = text[afterColon...].firstIndex(of: ":") else {
                    buffer.append(contentsOf: text[index...])
                    break
                }
                let shortcode = String(text[afterColon..<end])
                if shortcodes.contains(shortcode) {
                    if !buffer.isEmpty { pieces.append(.text(buffer)); buffer = "" }
                    pieces.append(.emoji(shortcode))
                    index = text.index(after: end)
                } else {
                    buffer.append(":")
                    index = afterColon
                }
            }
            if !buffer.isEmpty { pieces.append(.text(buffer)) }
            return pieces
        }

        /// Reads a `name="value"` pair or a `name='value'` pair from a tag.
        private static func attribute(_ name: String, in tag: String) -> String? {
            guard let nameRange = tag.range(of: "\(name)=", options: [.caseInsensitive]) else { return nil }
            var rest = tag[nameRange.upperBound...]
            guard let quote = rest.first else { return nil }
            if quote == "\"" || quote == "'" {
                rest = rest.dropFirst()
                guard let end = rest.firstIndex(of: quote) else { return nil }
                return String(rest[..<end])
            }
            return String(rest.prefix { !$0.isWhitespace && $0 != ">" })
        }

        private static let namedEntities: [String: String] = [
            "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
            "nbsp": "\u{00A0}", "hellip": "…", "mdash": "—", "ndash": "–",
            "laquo": "«", "raquo": "»", "ldquo": "“", "rdquo": "”",
            "lsquo": "‘", "rsquo": "’", "middot": "·", "bull": "•", "copy": "©",
        ]

        static func decodeEntities(_ text: String) -> String {
            guard text.contains("&") else { return text }

            var output = ""
            var index = text.startIndex
            while index < text.endIndex {
                guard text[index] == "&",
                      let semicolon = text[index...].prefix(12).firstIndex(of: ";")
                else {
                    output.append(text[index])
                    index = text.index(after: index)
                    continue
                }

                let entity = String(text[text.index(after: index)..<semicolon])
                if let named = namedEntities[entity.lowercased()] {
                    output += named
                } else if entity.hasPrefix("#"),
                          let scalar = numericScalar(entity.dropFirst()) {
                    output.unicodeScalars.append(scalar)
                } else {
                    output += "&\(entity);"
                }
                index = text.index(after: semicolon)
            }
            return output
        }

        private static func numericScalar(_ digits: some StringProtocol) -> Unicode.Scalar? {
            let isHex = digits.first == "x" || digits.first == "X"
            let body = isHex ? digits.dropFirst() : digits[digits.startIndex...]
            return UInt32(body, radix: isHex ? 16 : 10).flatMap(Unicode.Scalar.init)
        }
    }
}

// MARK: - Ingest

/// One piece of text that needs the HTML reader, with the emoji that belong to
/// it.
nonisolated struct RichContentPiece: Hashable, Sendable {
    let html: String
    let shortcodes: Set<String>

    init(html: String, emoji: [Mastodon.Emoji]?) {
        self.html = html
        self.shortcodes = Set((emoji ?? []).map(\.shortcode))
    }
}

/// An item of a list whose text needs the HTML reader.
///
/// `PagedListModel` reads every piece of a page before the rows appear. The
/// parser thus operates once, away from the main actor, and not inside `body`
/// during a scroll movement.
nonisolated protocol RichContentSource {
    var richContentPieces: [RichContentPiece] { get }
}

nonisolated extension Mastodon.Status: RichContentSource {
    var richContentPieces: [RichContentPiece] {
        let post = displayed
        var pieces = [
            RichContentPiece(html: post.html, emoji: post.emojis),
            RichContentPiece(html: post.account.bestDisplayName, emoji: post.account.emojis),
        ]
        if let booster = boostedBy {
            pieces.append(RichContentPiece(html: booster.bestDisplayName, emoji: booster.emojis))
        }
        return pieces
    }
}

nonisolated extension Mastodon.Notification: RichContentSource {
    var richContentPieces: [RichContentPiece] {
        [RichContentPiece(html: account.bestDisplayName, emoji: account.emojis)]
            + (status?.richContentPieces ?? [])
    }
}

nonisolated extension Mastodon.Conversation: RichContentSource {
    var richContentPieces: [RichContentPiece] {
        lastStatus?.richContentPieces ?? []
    }
}

// MARK: - Cache

/// Keeps the result for the text of each post.
///
/// SwiftUI makes the body of a cell again at each scroll movement and at each
/// change of the state. Without this cache, the parser reads the same HTML
/// again each time.
@MainActor
final class RichContentCache {
    static let shared = RichContentCache()

    private let cache = NSCache<Key, Entry>()

    private init() {
        cache.countLimit = 600
    }

    func content(html: String, emoji: [Mastodon.Emoji]?) -> RichContent {
        content(for: RichContentPiece(html: html, emoji: emoji))
    }

    func content(for piece: RichContentPiece) -> RichContent {
        let key = Key(piece)
        if let hit = cache.object(forKey: key) { return hit.content }

        let parsed = RichContent.parse(html: piece.html, knownEmoji: piece.shortcodes)
        cache.setObject(Entry(parsed), forKey: key)
        return parsed
    }

    /// Reads a whole page away from the main actor and keeps each result.
    ///
    /// One task reads the pieces one after the other. A page holds many short
    /// values, thus a task for each one would cost more than the work itself.
    /// The important part is that no piece is read on the main actor.
    func warm(_ pieces: [RichContentPiece]) async {
        var wanted: [RichContentPiece] = []
        var seen = Set<RichContentPiece>()
        for piece in pieces where !piece.html.isEmpty {
            guard seen.insert(piece).inserted, cache.object(forKey: Key(piece)) == nil else { continue }
            wanted.append(piece)
        }
        guard !wanted.isEmpty else { return }

        let parsed = await Task.detached(priority: .userInitiated) {
            wanted.map { ($0, RichContent.parse(html: $0.html, knownEmoji: $0.shortcodes)) }
        }.value

        for (piece, content) in parsed {
            cache.setObject(Entry(content), forKey: Key(piece))
        }
    }

    /// `NSCache` needs a key of a class type. This one holds the parts of the
    /// piece, thus a lookup needs no new text value for each cell.
    private nonisolated final class Key: NSObject {
        let piece: RichContentPiece

        init(_ piece: RichContentPiece) {
            self.piece = piece
        }

        override var hash: Int { piece.hashValue }

        override func isEqual(_ object: Any?) -> Bool {
            (object as? Key).map { $0.piece == piece } ?? false
        }
    }

    private final class Entry {
        let content: RichContent
        init(_ content: RichContent) { self.content = content }
    }
}
