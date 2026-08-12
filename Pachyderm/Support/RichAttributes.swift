//
//  RichAttributes.swift
//  Pachyderm
//

import Foundation

/// Marks one character as a custom emoji. The value is the shortcode with no
/// colons.
///
/// The parser writes the attribute on a single placeholder character.
/// `RichText` reads it and puts an image in the place of that character. The
/// post thus stays one `AttributedString` value: a view can show it, a screen
/// reader can read it, and an editor can change it.
nonisolated enum CustomEmojiAttribute: AttributedStringKey {
    typealias Value = String
    static let name = "customEmoji"
}

extension AttributeScopes {
    /// The attributes of this app together with the attributes of Foundation.
    /// One scope for both keeps `\.link` and `\.inlinePresentationIntent` in
    /// reach of the same lookup as `\.customEmoji`.
    nonisolated struct PachydermAttributes: AttributeScope {
        let customEmoji: CustomEmojiAttribute
        let foundation: FoundationAttributes
    }

    nonisolated var pachyderm: PachydermAttributes.Type { PachydermAttributes.self }
}

extension AttributeDynamicLookup {
    /// Lets `text.customEmoji` and `runs[\.customEmoji]` find the key above.
    nonisolated subscript<Key: AttributedStringKey>(
        dynamicMember keyPath: KeyPath<AttributeScopes.PachydermAttributes, Key>
    ) -> Key {
        self[Key.self]
    }
}
