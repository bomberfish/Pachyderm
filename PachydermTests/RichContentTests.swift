//
//  RichContentTests.swift
//  PachydermTests
//

import Foundation
import Testing

@testable import Pachyderm

/// One piece of parsed content, flat and comparable.
///
/// The tests never look at the storage of `RichContent` directly. They compare
/// this value instead. Thus a change of the storage needs a change of only the
/// `flatten` function, and each expectation stays the same.
private enum Segment: Equatable, CustomStringConvertible {
    case text(String, InlinePresentationIntent?, URL?)
    case emoji(String)

    static func plain(_ value: String) -> Segment { .text(value, nil, nil) }

    var description: String {
        switch self {
        case .text(let value, let intent, let link):
            var parts = ["\"\(value)\""]
            if let intent { parts.append("intent: \(intent.rawValue)") }
            if let link { parts.append("link: \(link.absoluteString)") }
            return "text(\(parts.joined(separator: ", ")))"
        case .emoji(let shortcode):
            return "emoji(\(shortcode))"
        }
    }
}

private func flatten(_ content: RichContent) -> [Segment] {
    var segments: [Segment] = []
    // The emoji attribute divides the text. Each part between two emoji then
    // divides again at each change of style.
    for (shortcode, emojiRange) in content.text.runs[\.customEmoji] {
        if let shortcode {
            segments.append(.emoji(shortcode))
            continue
        }
        let part = content.text[emojiRange]
        for piece in part.runs {
            segments.append(
                .text(
                    String(content.text[piece.range].characters),
                    piece.inlinePresentationIntent,
                    piece.link
                )
            )
        }
    }
    return segments
}

private func parse(_ html: String, emoji: Set<String> = []) -> [Segment] {
    flatten(RichContent.parse(html: html, knownEmoji: emoji))
}

// MARK: - Text and blocks

@Suite("Rich content: text")
struct RichContentTextTests {
    @Test("Empty input gives empty content")
    func empty() {
        let content = RichContent.parse(html: "")
        #expect(content.text.characters.isEmpty)
        #expect(content.plainText.isEmpty)
        #expect(content.isEmpty)
    }

    @Test("A paragraph loses its tags")
    func paragraph() {
        #expect(parse("<p>Hello world</p>") == [.plain("Hello world")])
    }

    @Test("Two paragraphs get an empty line between them")
    func twoParagraphs() {
        #expect(parse("<p>one</p><p>two</p>") == [.plain("one\n\ntwo")])
    }

    @Test("The empty line after the last paragraph goes away")
    func trailingBlankLine() {
        let content = RichContent.parse(html: "<p>only</p>")
        #expect(content.plainText == "only")
        #expect(flatten(content) == [.plain("only")])
    }

    @Test("A break tag becomes one new line")
    func lineBreak() {
        #expect(parse("<p>one<br>two</p>") == [.plain("one\ntwo")])
        #expect(parse("<p>one<br />two</p>") == [.plain("one\ntwo")])
    }

    @Test("An unknown tag disappears but keeps its text")
    func unknownTag() {
        #expect(parse("<p>a <mark>b</mark> c</p>") == [.plain("a b c")])
    }

    @Test("A comment disappears")
    func comment() {
        #expect(parse("<p>a<!-- hidden -->b</p>") == [.plain("ab")])
    }

    @Test("A tag with no end character stays as text")
    func unterminatedTag() {
        #expect(parse("a < b") == [.plain("a < b")])
    }

    @Test("A close tag with no open tag does not break the parser")
    func strayCloseTag() {
        #expect(parse("</strong>plain</em>") == [.plain("plain")])
    }
}

// MARK: - Styles

@Suite("Rich content: styles")
struct RichContentStyleTests {
    @Test("Strong and bold both give the bold style")
    func bold() {
        #expect(
            parse("<p>a <strong>b</strong></p>") == [
                .plain("a "),
                .text("b", .stronglyEmphasized, nil),
            ]
        )
        #expect(parse("<b>b</b>") == [.text("b", .stronglyEmphasized, nil)])
    }

    @Test("Emphasis, strike-through and code each give their style")
    func otherStyles() {
        #expect(parse("<em>e</em>") == [.text("e", .emphasized, nil)])
        #expect(parse("<i>e</i>") == [.text("e", .emphasized, nil)])
        #expect(parse("<del>d</del>") == [.text("d", .strikethrough, nil)])
        #expect(parse("<s>d</s>") == [.text("d", .strikethrough, nil)])
        #expect(parse("<code>c</code>") == [.text("c", .code, nil)])
    }

    @Test("Two styles together give both")
    func combinedStyles() {
        #expect(
            parse("<strong><em>x</em></strong>") == [
                .text("x", [.stronglyEmphasized, .emphasized], nil)
            ]
        )
    }

    @Test("The same tag twice keeps the style until the last close tag")
    func nestedSameTag() {
        // The parser counts the tags. It does not use a true or false value.
        #expect(
            parse("<strong><strong>x</strong>y</strong>") == [
                .text("xy", .stronglyEmphasized, nil)
            ]
        )
    }
}

// MARK: - Links

@Suite("Rich content: links")
struct RichContentLinkTests {
    @Test("A link puts its address on the text")
    func link() {
        #expect(
            parse("<a href=\"https://example.com\">site</a>") == [
                .text("site", nil, URL(string: "https://example.com"))
            ]
        )
    }

    @Test("A single quoted address also works")
    func singleQuotedHref() {
        #expect(
            parse("<a href='https://example.com'>site</a>") == [
                .text("site", nil, URL(string: "https://example.com"))
            ]
        )
    }

    @Test("An address with an entity becomes the true address")
    func hrefWithEntity() {
        #expect(
            parse("<a href=\"https://example.com/?a=1&amp;b=2\">q</a>") == [
                .text("q", nil, URL(string: "https://example.com/?a=1&b=2"))
            ]
        )
    }

    @Test("A link with no address gives text with no address")
    func linkWithoutHref() {
        #expect(parse("<a>bare</a>") == [.plain("bare")])
    }

    @Test("Text after a link has no address")
    func textAfterLink() {
        #expect(
            parse("<a href=\"https://example.com\">a</a>b") == [
                .text("a", nil, URL(string: "https://example.com")),
                .plain("b"),
            ]
        )
    }

    @Test("The three spans of a short link give the short text with three dots")
    func mastodonLinkShortening() {
        let html = """
            <a href="https://joinmastodon.org/about/very/long/path">\
            <span class="invisible">https://</span>\
            <span class="ellipsis">joinmastodon.org/about</span>\
            <span class="invisible">/very/long/path</span></a>
            """
        let url = URL(string: "https://joinmastodon.org/about/very/long/path")
        #expect(parse(html) == [.text("joinmastodon.org/about…", nil, url)])
    }

    @Test("A span with another class keeps its text")
    func mentionSpan() {
        let html = "<a href=\"https://example.com/@bob\">@<span>bob</span></a>"
        #expect(
            parse(html) == [
                .text("@bob", nil, URL(string: "https://example.com/@bob"))
            ]
        )
    }
}

// MARK: - Entities

@Suite("Rich content: entities")
struct RichContentEntityTests {
    @Test("A named entity becomes its character")
    func namedEntity() {
        #expect(parse("a &amp; b") == [.plain("a & b")])
        #expect(parse("5 &lt; 6 &gt; 4") == [.plain("5 < 6 > 4")])
        #expect(parse("&mdash;") == [.plain("—")])
    }

    @Test("A number entity becomes its character")
    func numericEntity() {
        #expect(parse("caf&#233;") == [.plain("café")])
        #expect(parse("&#x1F600;") == [.plain("😀")])
    }

    @Test("An entity the parser does not know stays as it is")
    func unknownEntity() {
        // The table holds only the common names. `&egrave;` is not in it.
        #expect(parse("cr&egrave;me") == [.plain("cr&egrave;me")])
    }

    @Test("A lone ampersand stays as it is")
    func bareAmpersand() {
        #expect(parse("a & b") == [.plain("a & b")])
    }
}

// MARK: - Custom emoji

@Suite("Rich content: custom emoji")
struct RichContentEmojiTests {
    @Test("A known shortcode becomes a separate part")
    func knownShortcode() {
        #expect(
            parse("<p>hi :blobcat: there</p>", emoji: ["blobcat"]) == [
                .plain("hi "),
                .emoji("blobcat"),
                .plain(" there"),
            ]
        )
    }

    @Test("An unknown shortcode stays as text")
    func unknownShortcode() {
        #expect(parse("<p>hi :nope: there</p>", emoji: ["blobcat"]) == [.plain("hi :nope: there")])
    }

    @Test("The plain text keeps the colons")
    func plainTextKeepsShortcode() {
        let content = RichContent.parse(html: "hi :blobcat:", knownEmoji: ["blobcat"])
        #expect(content.plainText == "hi :blobcat:")
    }

    @Test("A shortcode keeps the style of the text around it")
    func shortcodeInsideStyle() {
        #expect(
            parse("<strong>a :blobcat: b</strong>", emoji: ["blobcat"]) == [
                .text("a ", .stronglyEmphasized, nil),
                .emoji("blobcat"),
                .text(" b", .stronglyEmphasized, nil),
            ]
        )
    }

    @Test("Two shortcodes together each become a part")
    func adjacentShortcodes() {
        #expect(
            parse(":a::b:", emoji: ["a", "b"]) == [
                .emoji("a"),
                .emoji("b"),
            ]
        )
    }

    @Test("A colon with no pair does not remove text")
    func unpairedColon() {
        #expect(parse("time: 12:00", emoji: ["blobcat"]) == [.plain("time: 12:00")])
    }
}
