//
//  MastodonHTML.swift
//  Pachyderm
//

import Foundation

/// The text of a post in parts. SwiftUI can show each part directly.
///
/// A custom emoji becomes a separate part. Thus the view can put an image
/// between two parts of text.
nonisolated struct RichContent: Hashable, Sendable {
    enum Run: Hashable, Sendable {
        case text(AttributedString)
        /// A custom emoji. The value is the shortcode without the two colons.
        case emoji(String)
    }

    var runs: [Run]
    /// The text with no style. Use it for a screen reader and for a preview.
    var plainText: String

    var isEmpty: Bool { plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    static let empty = RichContent(runs: [], plainText: "")
}

// MARK: - Parser

extension RichContent {
    /// Reads the small group of HTML tags that Mastodon sends.
    ///
    /// This function replaces
    /// `NSAttributedString(data:options:[.documentType: .html])`. That
    /// initializer uses WebKit, thus it must run on the main thread. The
    /// earlier code called it from a background task. Such a call has no
    /// defined result. When it operates, it also stops the scroll movement.
    ///
    /// - Parameter knownEmoji: The shortcodes for this post from the server.
    ///   The function makes a separate part for only these shortcodes. Other
    ///   text between two colons does not change.
    static func parse(html: String, knownEmoji: Set<String> = []) -> RichContent {
        guard !html.isEmpty else { return .empty }
        var parser = Parser(html: html, knownEmoji: knownEmoji)
        return parser.parse()
    }

    private struct Parser {
        let html: String
        let knownEmoji: Set<String>

        private var runs: [Run] = []
        private var current = AttributedString()
        private var plain = ""

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

        init(html: String, knownEmoji: Set<String>) {
            self.html = html
            self.knownEmoji = knownEmoji
        }

        mutating func parse() -> RichContent {
            var index = html.startIndex
            var textStart = index

            while index < html.endIndex {
                if html[index] == "<" {
                    append(text: String(html[textStart..<index]))
                    guard let close = html[index...].firstIndex(of: ">") else {
                        // The tag has no end character. Use the remainder as
                        // text.
                        textStart = index
                        break
                    }
                    handle(tag: String(html[html.index(after: index)..<close]))
                    index = html.index(after: close)
                    textStart = index
                } else {
                    index = html.index(after: index)
                }
            }
            append(text: String(html[textStart..<html.endIndex]))

            flush()
            trimTrailingWhitespace()
            return RichContent(runs: runs, plainText: plain.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        // MARK: Tags

        private mutating func handle(tag raw: String) {
            let body = raw.trimmingCharacters(in: .whitespaces)
            guard !body.isEmpty, !body.hasPrefix("!") else { return }

            let isClosing = body.hasPrefix("/")
            let name = String(
                body.drop(while: { $0 == "/" })
                    .prefix(while: { !$0.isWhitespace && $0 != "/" && $0 != ">" })
            ).lowercased()

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
                } else if let href = Self.attribute("href", in: body),
                          let url = URL(string: Self.decodeEntities(href)) {
                    links.append(url)
                } else {
                    // Add an item also for a bad `href` value. The stack must
                    // keep one item for each `<a>` tag.
                    links.append(URL(string: "about:blank")!)
                }
            case "span":
                handleSpan(body: body, isClosing: isClosing)
            default:
                break
            }

            bold = max(0, bold)
            italic = max(0, italic)
            strikethrough = max(0, strikethrough)
            code = max(0, code)
        }

        /// Mastodon makes a long link shorter with three `span` elements:
        /// `<span class="invisible">https://</span><span class="ellipsis">example.com/a</span><span class="invisible">/long/path</span>`
        /// The parser removes the hidden parts. It puts three dots at the end
        /// of the short text.
        private mutating func handleSpan(body: String, isClosing: Bool) {
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

            let classes = Self.attribute("class", in: body) ?? ""
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

        private mutating func append(text raw: String) {
            guard !raw.isEmpty else { return }
            appendRaw(Self.decodeEntities(raw))
        }

        private mutating func appendRaw(_ text: String) {
            guard !text.isEmpty, invisibleDepth == 0 else { return }

            guard !knownEmoji.isEmpty else {
                appendStyled(text)
                return
            }
            for piece in Self.split(text, shortcodes: knownEmoji) {
                switch piece {
                case .text(let value):
                    appendStyled(value)
                case .emoji(let shortcode):
                    flush()
                    runs.append(.emoji(shortcode))
                    plain += ":\(shortcode):"
                }
            }
        }

        private mutating func appendStyled(_ text: String) {
            guard !text.isEmpty else { return }
            var piece = AttributedString(text)
            piece.mergeAttributes(attributes)
            current.append(piece)
            plain += text
        }

        private var attributes: AttributeContainer {
            var container = AttributeContainer()
            var intent: InlinePresentationIntent = []
            if bold > 0 { intent.insert(.stronglyEmphasized) }
            if italic > 0 { intent.insert(.emphasized) }
            if strikethrough > 0 { intent.insert(.strikethrough) }
            if code > 0 { intent.insert(.code) }
            if !intent.isEmpty { container.inlinePresentationIntent = intent }
            if let link = links.last, link.scheme != "about" { container.link = link }
            return container
        }

        private mutating func flush() {
            guard !current.characters.isEmpty else { return }
            runs.append(.text(current))
            current = AttributedString()
        }

        /// Removes the empty line at the end. Each `</p>` tag makes one.
        private mutating func trimTrailingWhitespace() {
            while case .text(var last)? = runs.last {
                guard let range = last.range(of: "\\s+$", options: .regularExpression) else { return }
                last.removeSubrange(range)
                if last.characters.isEmpty {
                    runs.removeLast()
                } else {
                    runs[runs.count - 1] = .text(last)
                    return
                }
            }
        }

        // MARK: Static helpers

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

// MARK: - Cache

/// Keeps the result for the text of each post.
///
/// SwiftUI makes the body of a cell again at each scroll movement and at each
/// change of the state. Without this cache, the parser reads the same HTML
/// again each time.
@MainActor
final class RichContentCache {
    static let shared = RichContentCache()

    private let cache = NSCache<NSString, Entry>()

    private init() {
        cache.countLimit = 600
    }

    func content(html: String, emoji: [Mastodon.Emoji]?) -> RichContent {
        let shortcodes = Set((emoji ?? []).map(\.shortcode))
        let key = "\(shortcodes.sorted().joined(separator: ","))|\(html)" as NSString

        if let hit = cache.object(forKey: key) { return hit.content }
        let parsed = RichContent.parse(html: html, knownEmoji: shortcodes)
        cache.setObject(Entry(parsed), forKey: key)
        return parsed
    }

    private final class Entry {
        let content: RichContent
        init(_ content: RichContent) { self.content = content }
    }
}
