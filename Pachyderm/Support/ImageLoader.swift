//
//  ImageLoader.swift
//  Pachyderm
//

import Foundation
import UIKit
import os

/// One image loader for the full app. It holds a cache of decoded images, and
/// it makes only one request for each image.
///
/// This class replaces the `CachedAsyncImage` code from a different project.
/// That code made a new `URLSession` object for each view. Thus each view made
/// a new connection, and the views had no common cache. It also decoded each
/// image on the main actor, and it used a force unwrap on its cache.
///
/// Two things are important for a timeline:
///
/// - **One request for each image.** The same avatar is in many cells at the
///   same time. Without this class each cell starts its own download.
/// - **A smaller image.** A server sends an avatar of 400 by 400 pixels for a
///   view of 44 points. It also sends very large attachments. A decode
///   operation at the full size uses most of the time. Thus the loader decodes
///   each image at the size on the screen.
actor ImageLoader {
    static let shared = ImageLoader()

    private let cache = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private let session: URLSession
    private let logger = Logger(subsystem: "ca.bomberfish.Pachyderm", category: "images")

    private init() {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 16 << 20, diskCapacity: 256 << 20)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
        // The cost of each item is a number of bytes. Thus the limit has a
        // clear meaning. 48 MB of decoded pixels holds the avatars and the
        // attachments of a small number of screens.
        cache.totalCostLimit = 48 << 20
    }

    /// - Parameter maxPixelSize: The length of the longest edge in pixels after
    ///   the decode operation. A `nil` value keeps the full size.
    func image(for url: URL, maxPixelSize: Int?) async -> UIImage? {
        let key = Self.key(url: url, maxPixelSize: maxPixelSize)

        if let cached = cache.object(forKey: key as NSString) { return cached }
        if let existing = inFlight[key] { return await existing.value }

        let task = Task<UIImage?, Never> { [session, logger] in
            do {
                let (data, response) = try await session.data(from: url)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    logger.debug("Image \(url.absoluteString, privacy: .public) -> \(http.statusCode)")
                    return nil
                }
                return Self.decode(data, maxPixelSize: maxPixelSize)
            } catch {
                if !(error is CancellationError) {
                    logger.debug("Image \(url.absoluteString, privacy: .public) failed: \(error.localizedDescription)")
                }
                return nil
            }
        }
        inFlight[key] = task

        let image = await task.value
        inFlight[key] = nil
        if let image {
            cache.setObject(image, forKey: key as NSString, cost: image.approximateBytes)
        }
        return image
    }

    private static func key(url: URL, maxPixelSize: Int?) -> String {
        "\(url.absoluteString)@\(maxPixelSize.map(String.init) ?? "full")"
    }

    /// Decodes the data off the main actor with ImageIO. It can also make the
    /// image smaller. ImageIO does not make a bitmap of the full size.
    private static func decode(_ data: Data, maxPixelSize: Int?) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [
            kCGImageSourceShouldCache: false,
        ] as CFDictionary) else {
            return nil
        }

        guard let maxPixelSize else {
            return CGImageSourceCreateImageAtIndex(source, 0, nil).map(UIImage.init(cgImage:))
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            // ImageIO cannot make a small image from some GIF files with
            // movement. Decode such a file at the full size.
            return CGImageSourceCreateImageAtIndex(source, 0, nil).map(UIImage.init(cgImage:))
        }
        return UIImage(cgImage: thumbnail)
    }
}

private extension UIImage {
    /// An approximate size of the decoded image. The cache uses it as the cost.
    ///
    /// The property is `nonisolated`, because the loader is an actor. The module
    /// makes `MainActor` the default. Without `nonisolated` the actor cannot
    /// read this property.
    nonisolated var approximateBytes: Int {
        guard let cgImage else { return 1 }
        return max(1, cgImage.bytesPerRow * cgImage.height)
    }
}
