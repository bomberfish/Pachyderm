//
//  AttachmentGrid.swift
//  Pachyderm
//

import AVKit
import SwiftUI

struct AttachmentGrid: View {
    let attachments: [Mastodon.MediaAttachment]
    let isSensitive: Bool

    @State private var isRevealed = false

    private var isHidden: Bool { isSensitive && !isRevealed }

    var body: some View {
        media
            .blur(radius: isHidden ? 28 : 0)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            // Without this modifier a touch goes to the attachment below the
            // blur effect.
            .allowsHitTesting(!isHidden)
            .overlay {
                if isHidden {
                    Button {
                        withAnimation(.snappy) { isRevealed = true }
                    } label: {
                        Label("Sensitive content", systemImage: "eye")
                            .font(.subheadline)
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.glassBackport)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isSensitive && isRevealed {
                    Button {
                        withAnimation(.snappy) { isRevealed = false }
                    } label: {
                        Image(systemName: "eye.slash")
                            .padding(6)
                    }
                    .buttonStyle(.glassBackport)
                    .padding(8)
                    .accessibilityLabel("Hide sensitive content")
                }
            }
            .animation(.snappy, value: isRevealed)
    }

    @ViewBuilder
    private var media: some View {
        if let only = attachments.first, attachments.count == 1 {
            AttachmentView(attachment: only)
                .aspectRatio(aspectRatio(of: only), contentMode: .fit)
        } else {
            VStack(spacing: 4) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 4) {
                        ForEach(row) { attachment in
                            AttachmentView(attachment: attachment)
                                .aspectRatio(3 / 2, contentMode: .fill)
                                .frame(maxWidth: .infinity)
                                .clipped()
                        }
                        // One attachment in the last row keeps the width of one
                        // column. It does not fill the two columns.
                        if row.count == 1 {
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

    private var rows: [[Mastodon.MediaAttachment]] {
        stride(from: 0, to: attachments.count, by: 2).map { start in
            Array(attachments[start..<min(start + 2, attachments.count)])
        }
    }

    /// The function keeps the value between two limits. Thus an image of 1 by
    /// 5000 pixels cannot move the timeline off the screen. An attachment
    /// without a `meta` object also gets a correct size.
    private func aspectRatio(of attachment: Mastodon.MediaAttachment) -> Double {
        min(max(attachment.aspectRatio ?? 4 / 3, 0.6), 2.2)
    }
}

/// One attachment. It is an image, a video image, an audio row, or a link.
struct AttachmentView: View {
    let attachment: Mastodon.MediaAttachment

    @State private var isPlaying = false
    @State private var isShowingAltText = false

    var body: some View {
        content
            .overlay(alignment: .bottomLeading) {
                if let description = attachment.description, !description.isEmpty {
                    Button("ALT") { isShowingAltText = true }
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.6), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(6)
                        .accessibilityLabel("Show image description")
                }
            }
            .alert("Description", isPresented: $isShowingAltText) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(attachment.description ?? "")
            }
            .fullScreenCover(isPresented: $isPlaying) {
                if let url = attachment.mediaURL {
                    VideoOverlay(url: url, loops: attachment.type == .gifv)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch attachment.type {
        case .image:
            preview
                .accessibilityLabel(attachment.description ?? "Image attachment")

        case .video, .gifv:
            preview
                .overlay {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white, .black.opacity(0.4))
                        .shadow(radius: 6)
                }
                .overlay(alignment: .bottomTrailing) {
                    if attachment.type == .gifv {
                        Text("GIF")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.6), in: Capsule())
                            .foregroundStyle(.white)
                            .padding(6)
                    }
                }
                // The app makes a player only for a video that plays. The
                // earlier cell made an `AVPlayer` object in its `body`
                // property. Thus each scroll movement made one player for each
                // video on the screen.
                .onTapGesture { isPlaying = true }
                .accessibilityLabel(attachment.description ?? "Video attachment")
                .accessibilityAddTraits(.isButton)

        case .audio:
            Label(attachment.description ?? "Audio attachment", systemImage: "waveform")
                .font(.subheadline)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onTapGesture { isPlaying = true }
                .accessibilityAddTraits(.isButton)

        case .unknown:
            if let url = attachment.mediaURL {
                Link(destination: url) {
                    Label(url.lastPathComponent, systemImage: "paperclip")
                        .font(.subheadline)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
    }

    private var preview: some View {
        RemoteImage(url: attachment.previewURL, targetSize: nil) {
            ZStack {
                Rectangle().fill(.quaternary)
                ProgressView()
            }
        }
    }
}

/// A video on the full screen. The app makes this view only after a touch. Thus
/// a timeline with many videos uses no extra memory.
private struct VideoOverlay: View {
    let url: URL
    let loops: Bool

    @Environment(\.dismiss) private var dismiss
    /// An `AVPlayerLooper` object controls a queue player. Thus the view uses
    /// this type. The alternative method is an observer for
    /// `AVPlayerItemDidPlayToEndTime`. That method gives a player that is not
    /// `Sendable` to a `@Sendable` closure.
    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VideoPlayer(player: player)
                .ignoresSafeArea()
        }
        .overlay(alignment: .topLeading) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .padding(8)
            }
            .buttonStyle(.glassBackport)
            .padding()
            .accessibilityLabel("Close")
        }
        .task {
            guard player == nil else { return }
            let player = AVQueuePlayer()
            let item = AVPlayerItem(url: url)
            if loops {
                // Mastodon sends a GIF as a video with no sound. The video
                // plays again and again.
                player.isMuted = true
                looper = AVPlayerLooper(player: player, templateItem: item)
            } else {
                player.insert(item, after: nil)
            }
            self.player = player
            player.play()
        }
        .onDisappear {
            player?.pause()
            looper?.disableLooping()
        }
    }
}
