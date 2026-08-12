//
//  RemoteImage.swift
//  Pachyderm
//

import SwiftUI

/// Gets an image from a server with `ImageLoader`. The loader decodes the image
/// at the size on the screen.
///
/// This view does not use `AsyncImage`. That decision is intentional.
/// `AsyncImage` has no common cache. Thus a scroll movement in a timeline
/// downloads each avatar again after it comes back to the screen.
struct RemoteImage<Placeholder: View>: View {
    private let url: URL?
    private let targetSize: CGSize?
    private let contentMode: ContentMode
    private let placeholder: () -> Placeholder

    @State private var image: UIImage?

    @Environment(\.displayScale) private var displayScale

    /// - Parameter targetSize: The size of the image on the screen in points.
    ///   The view selects the decode size from this value. A `nil` value keeps
    ///   the full size.
    init(
        url: URL?,
        targetSize: CGSize?,
        contentMode: ContentMode = .fill,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.targetSize = targetSize
        self.contentMode = contentMode
        self.placeholder = placeholder
    }

    var body: some View {
        content
            // The task uses the URL as its id. Thus a cell for a new post loads
            // the new image. It does not show the old image. The system also
            // stops the task when the cell leaves the screen.
            .task(id: url) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: contentMode)
                .transition(.opacity)
        } else {
            placeholder()
        }
    }

    private func load() async {
        guard let url else {
            image = nil
            return
        }
        if image != nil { return }

        let maxPixelSize = targetSize.map { size in
            Int((max(size.width, size.height) * displayScale).rounded(.up))
        }
        let loaded = await ImageLoader.shared.image(for: url, maxPixelSize: maxPixelSize)
        guard !Task.isCancelled else { return }
        // After an unsuccessful load the view keeps the placeholder. The
        // `.task(id:)` modifier tries again when a cell gets the same URL.
        withAnimation(.easeOut(duration: 0.15)) {
            image = loaded
        }
    }
}

extension RemoteImage where Placeholder == AnyView {
    /// A `RemoteImage` view with the usual grey placeholder. The placeholder
    /// has no movement.
    init(url: URL?, targetSize: CGSize?, contentMode: ContentMode = .fill) {
        self.init(url: url, targetSize: targetSize, contentMode: contentMode) {
            AnyView(Rectangle().fill(.quaternary))
        }
    }
}
