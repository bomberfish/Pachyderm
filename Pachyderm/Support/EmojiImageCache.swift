//
//  EmojiImageCache.swift
//  Pachyderm
//

import SwiftUI
import UIKit

/// Keeps the ready `Image` value of each custom emoji.
///
/// `ImageLoader` keeps the pixels, but each view then made its own `Image`
/// value and its own scale wrapper, and it kept them in its own state. A cell
/// that appeared again thus showed the shortcode until its task ended, and a
/// timeline with the same emoji in twenty cells held twenty copies.
///
/// This cache answers while a view makes its body. An emoji that is already
/// here appears at once.
@MainActor
final class EmojiImageCache {
    static let shared = EmojiImageCache()

    /// A guard against growth with no end. One image is small, but a long
    /// session on a server with many custom emoji meets many of them.
    private static let limit = 500

    private struct Key: Hashable {
        let url: URL
        /// The height in whole points. Dynamic Type gives a small group of
        /// sizes, thus this value has few forms.
        let height: Int

        init(url: URL, height: CGFloat) {
            self.url = url
            self.height = Int(height.rounded())
        }
    }

    private var images: [Key: Image] = [:]

    private init() {}

    /// The image, when it is already here. The function does no work and waits
    /// for nothing, thus a view can call it from its body.
    func image(for url: URL, height: CGFloat) -> Image? {
        images[Key(url: url, height: height)]
    }

    /// Loads the image and keeps it. The result is true when the image is in
    /// the cache after the call.
    @discardableResult
    func load(url: URL, height: CGFloat, scale: CGFloat) async -> Bool {
        let key = Key(url: url, height: height)
        if images[key] != nil { return true }

        // The emoji covers `height` points, thus that many device pixels are
        // enough. The earlier code asked for twice as many and made a bitmap
        // of four times the area.
        let maxPixelSize = Int((height * scale).rounded(.up))
        guard let loaded = await ImageLoader.shared.image(for: url, maxPixelSize: maxPixelSize) else {
            return false
        }

        if images.count >= Self.limit { images.removeAll(keepingCapacity: true) }
        images[key] = Image(uiImage: loaded.scaled(toHeight: height))
        return true
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
