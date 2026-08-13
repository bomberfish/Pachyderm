//
//  PostCell.swift
//  Pachyderm
//
//  Created by Hariz Shirazi on 2025-06-13.
//

import SwiftUI

struct PostCell: View {
    @Binding var status: Mastodon.Status

    var isDetail = false
    var showsActions = true

    @Environment(MastoAPI.self) private var api
    @Environment(ErrorPresenter.self) private var errors
    @Environment(Navigator.self) private var navigator

    @State private var isRevealed = false
    @State private var isComposingReply = false

    /// The status with the content on the screen. For a boost it is the
    /// original post.
    private var post: Mastodon.Status { status.displayed }

    private var isContentHidden: Bool {
        post.hasContentWarning && !isRevealed && !isDetail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let booster = status.boostedBy {
                boostBanner(booster)
            }

            header

            if post.hasContentWarning {
                contentWarning
            }

            if !isContentHidden {
                RichText(html: post.html, emoji: post.emojis)
                    .font(isDetail ? .title3 : .body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !post.attachments.isEmpty {
                    AttachmentGrid(
                        attachments: post.attachments,
                        isSensitive: post.sensitive == true
                    )
                }
            }

            if showsActions {
                PostActions(
                    post: post,
                    isDetail: isDetail,
                    onOpen: { navigator.open(post) },
                    onReply: { isComposingReply = true },
                    onFavourite: toggleFavourite,
                    onBoost: toggleBoost,
                    onBookmark: toggleBookmark
                )
            }
        }
        .padding(.vertical, 6)
        .contentShape(.rect)
        .onTapGesture {
            guard !isDetail else { return }
            navigator.open(post)
        }
        .accessibilityElement(children: .contain)
        .sheet(isPresented: $isComposingReply) {
            ComposeView(inReplyTo: post) { _ in
                var updated = post
                updated.repliesCount += 1
                withAnimation(.snappy) { write(updated) }
            }
        }
    }

    // MARK: - Pieces

    private func boostBanner(_ booster: Mastodon.Account) -> some View {
        Button {
            navigator.open(booster)
        } label: {
            Label {
                Text("\(booster.bestDisplayName) boosted")
            } icon: {
                Image(systemName: "arrow.2.squarepath")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                navigator.open(post.account)
            } label: {
                HStack(spacing: 8) {
                    AvatarView(account: post.account, size: .regular)

                    VStack(alignment: .leading, spacing: 1) {
                        RichText(
                            html: post.account.bestDisplayName,
                            emoji: post.account.emojis
                        )
                        .font(.headline)
                        .lineLimit(1)

                        Text(verbatim: "@\(post.account.acct)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 4)
            if showsActions {
                VStack(alignment: .trailing, spacing: 2) {
                    if let createdAt = post.createdAt {
                        Text(createdAt, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                    }
                    HStack(spacing: 3) {
                        if post.localOnly == true {
                            Image(systemName: "house.slash")
                                .accessibilityLabel("Local only")
                        }
                        if let visibility = post.visibility, visibility != .public {
                            Image(systemName: visibility.icon)
                                .accessibilityLabel(visibility.description)
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var contentWarning: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(post.spoilerText ?? "Sensitive content", systemImage: "eye.slash")
                .font(.headline)

            if !isDetail {
                Button {
                    withAnimation(.snappy) { isRevealed.toggle() }
                } label: {
                    Label(
                        isRevealed ? "Hide content" : "Show content",
                        systemImage: isRevealed ? "chevron.up" : "chevron.down"
                    )
                    .contentTransition(.symbolEffect(.replace))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassBackport)
            }
        }
    }

    // MARK: - Interactions

    /// Puts a new status into the binding. For a boost it puts the status into
    /// the inner post.
    private func write(_ updated: Mastodon.Status) {
        if status.reblog != nil {
            status.reblog = Indirect(updated)
        } else {
            status = updated
        }
    }

    /// Makes the change on the screen immediately. Then the app replaces the
    /// status with the copy from the server. After an unsuccessful request the
    /// app puts the original status back.
    private func interact(
        optimistically change: (inout Mastodon.Status) -> Void,
        request: @escaping (Mastodon.Status) async throws -> Mastodon.Status,
        failureTitle: String
    ) {
        let original = post
        Haptic.shared.play(.light)

        var optimistic = original
        change(&optimistic)
        withAnimation(.snappy) { write(optimistic) }

        Task {
            do {
                write(try await request(original))
            } catch {
                write(original)
                errors.present(error, title: failureTitle)
            }
        }
    }

    private func toggleFavourite() {
        let target = !(post.favourited ?? false)
        let api = api
        interact(
            optimistically: { post in
                post.favourited = target
                post.favouritesCount = max(0, post.favouritesCount + (target ? 1 : -1))
            },
            request: { post in try await api.setFavourited(target, on: post) },
            failureTitle: target ? "Couldn't favourite" : "Couldn't unfavourite"
        )
    }

    private func toggleBoost() {
        let target = !(post.reblogged ?? false)
        let api = api
        interact(
            optimistically: { post in
                post.reblogged = target
                post.reblogsCount = max(0, post.reblogsCount + (target ? 1 : -1))
            },
            request: { post in try await api.setReblogged(target, on: post) },
            failureTitle: target ? "Couldn't boost" : "Couldn't unboost"
        )
    }

    private func toggleBookmark() {
        let target = !(post.bookmarked ?? false)
        let api = api
        interact(
            optimistically: { post in post.bookmarked = target },
            request: { post in try await api.setBookmarked(target, on: post) },
            failureTitle: target ? "Couldn't bookmark" : "Couldn't remove bookmark"
        )
    }
}

// MARK: - Action bar

/// The buttons for reply, favourite, boost, bookmark and share. The row also
/// has a menu with the other commands.
private struct PostActions: View {
    let post: Mastodon.Status
    let isDetail: Bool
    let onOpen: () -> Void
    let onReply: () -> Void
    let onFavourite: () -> Void
    let onBoost: () -> Void
    let onBookmark: () -> Void

    /// The height of every button in the row. It gives each command a touch
    /// area that a finger can reach without care.
    private let hitHeight: CGFloat = 36

    /// A boost has no result for a post that only its receivers can read.
    private var canBoost: Bool {
        post.visibility != .private && post.visibility != .direct
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onReply) {
                count(icon: "arrowshape.turn.up.left", value: post.repliesCount)
            }
            .accessibilityLabel("Reply")

            Button(action: onFavourite) {
                count(
                    icon: post.favourited == true ? "star.fill" : "star",
                    value: post.favouritesCount,
                    tint: post.favourited == true ? .yellow : nil
                )
            }
            .accessibilityLabel(post.favourited == true ? "Unfavourite" : "Favourite")

            Button(action: onBoost) {
                count(
                    icon: "arrow.2.squarepath",
                    value: post.reblogsCount,
                    tint: post.reblogged == true ? .green : nil
                )
            }
            .accessibilityLabel(post.reblogged == true ? "Unboost" : "Boost")
            .disabled(!canBoost)

            Spacer(minLength: 0)

            Button(action: onBookmark) {
                actionIcon(
                    post.bookmarked == true ? "bookmark.fill" : "bookmark",
                    isHighlighted: post.bookmarked == true
                )
            }
            .accessibilityLabel(post.bookmarked == true ? "Remove bookmark" : "Bookmark")

            if let permalink = post.permalink {
                ShareLink(item: permalink) {
                    actionIcon("square.and.arrow.up")
                }
                .accessibilityLabel("Share")
            }

            Menu {
                if !isDetail {
                    Button("Open Post", systemImage: "text.bubble", action: onOpen)
                }
                if let permalink = post.permalink {
                    Link(destination: permalink) {
                        Label("Open in Browser", systemImage: "safari")
                    }
                    Button("Copy Link", systemImage: "link") {
                        UIPasteboard.general.url = permalink
                    }
                }
                Button("Copy Text", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = RichContentCache.shared
                        .content(html: post.html, emoji: post.emojis)
                        .plainText
                }
            } label: {
                actionIcon("ellipsis")
            }
            .accessibilityLabel("More actions")
        }
        .font(.body)
        .foregroundStyle(.secondary)
        .buttonStyle(.plain)
        .padding(.top, 2)
    }

    private func count(icon: String, value: Int, tint: Color? = nil) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .contentTransition(.symbolEffect(.replace))
            if value > 0 {
                Text(value, format: .number.notation(.compactName))
                    .contentTransition(.numericText())
                    .monospacedDigit()
                    .font(.subheadline)
            }
        }
        .foregroundStyle(tint ?? .secondary)
        // The minimum width keeps the arrangement of the row. A count with more
        // digits does not move the other buttons.
        .frame(minWidth: 46, minHeight: hitHeight, alignment: .leading)
        .contentShape(.rect)
    }

    /// A button with no count. It has the same touch area as a button with a
    /// count.
    private func actionIcon(_ name: String, isHighlighted: Bool = false) -> some View {
        Image(systemName: name)
            .contentTransition(.symbolEffect(.replace))
            .foregroundStyle(isHighlighted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .frame(minWidth: hitHeight, minHeight: hitHeight)
            .contentShape(.rect)
    }
}

#Preview("Post") {
    ScrollView {
        VStack(spacing: 0) {
            PostCell(status: .constant(.preview))
            Divider()
            PostCell(status: .constant(.previewBoost))
            Divider()
            PostCell(status: .constant(.previewSensitive))
        }
        .padding(.horizontal)
    }
    .previewEnvironment()
}
