//
//  AccountView.swift
//  Pachyderm
//
//  Created by Hariz Shirazi on 2025-06-13.
//

import SwiftUI

struct AccountView: View {
    @Environment(MastoAPI.self) private var api
    @Environment(ErrorPresenter.self) private var errors

    @State private var account: Mastodon.Account
    @State private var feed: Mastodon.AccountFeed = .posts
    @State private var model: PagedListModel<Mastodon.Status>?

    /// The largest width of the feed control. The three names are short, thus a
    /// control across the full width puts a large empty space around each name.
    /// The value increases with the text size of the user.
    @ScaledMetric(relativeTo: .body) private var feedPickerWidth: CGFloat = 300

    init(account: Mastodon.Account) {
        _account = State(initialValue: account)
    }

    var body: some View {
        Group {
            if let model {
                PostList(model: model) {
                    VStack(spacing: 12) {
                        AccountHeader(account: account)

                        Picker("Show", selection: $feed) {
                            ForEach(Mastodon.AccountFeed.allCases) { feed in
                                Text(feed.description).tag(feed)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: feedPickerWidth)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(account.bestDisplayName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model == nil {
                model = PagedListModel(source: source(for: feed))
            }
            await refreshProfile()
        }
        .onChange(of: feed) { _, newFeed in
            model?.replaceSource(source(for: newFeed))
        }
    }

    private func source(for feed: Mastodon.AccountFeed) -> PagedListModel<Mastodon.Status>.Source {
        let api = api
        let id = account.id
        return { olderThan in
            try await api.statuses(byAccount: id, feed: feed, olderThan: olderThan)
        }
    }

    private func refreshProfile() async {
        do {
            account = try await api.account(id: account.id)
        } catch is CancellationError {
            // The user left the screen.
        } catch {
            errors.present(error, title: "Couldn't load this profile")
        }
    }
}

// MARK: - Header

struct AccountHeader: View {
    let account: Mastodon.Account

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            banner

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                RichText(html: account.bestDisplayName, emoji: account.emojis)
                    .font(.title2.weight(.semibold))
                if account.locked == true {
                    Image(systemName: "lock.fill").foregroundStyle(.secondary)
                }
                if account.bot == true {
                    Image(systemName: "gearshape.2.fill").foregroundStyle(.secondary)
                }
            }

            Text(verbatim: "@\(account.acct)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if let note = account.note, !note.isEmpty {
                RichText(html: note, emoji: account.emojis)
                    .font(.callout)
            }

            if let fields = account.fields, !fields.isEmpty {
                // The name goes above the value. Both start at the left edge of
                // the card. Two earlier layouts put the name and the value on
                // one line: one gave the name a width of 90 points, the other
                // put the value at the right edge. Each layout made a large
                // empty space in the middle of a row, and a long name made that
                // space larger. A column of names with a maximum width is not a
                // solution, because a name that is longer than that width then
                // writes over the value.
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(fields) { field in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(field.name)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)

                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                RichText(html: field.value, emoji: account.emojis)
                                    .font(.caption)
                                if field.isVerified {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundStyle(.green)
                                        .accessibilityLabel("Verified")
                                        .font(.caption)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)

                        if field.id != fields.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            // The three counts go on one line. At a large text size that line
            // is too long, and the earlier row then wrote each name across two
            // lines with a hyphen. The second layout gives one count per line.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { stats }
                VStack(alignment: .leading, spacing: 4) { stats }
            }
            .font(.footnote)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The shape gives the size of the banner. The image is only an overlay.
    /// Thus the image cannot change the layout.
    ///
    /// The image gave the size before. That image keeps the ratio of its sides,
    /// and it fills the space. A header image is usually 3 to 1 or wider. With a
    /// height of 140 points such an image asks for a width of more than 420
    /// points, and a `maxWidth` value does not make that width smaller. The
    /// header then became wider than the screen, and each line of the header
    /// moved off both edges of the screen. A profile with no header image did
    /// not show the fault, because the grey shape accepts each width.
    private var banner: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.quaternary)
            .frame(height: 140)
            .frame(maxWidth: .infinity)
            .overlay {
                RemoteImage(url: account.headerURL, targetSize: CGSize(width: 600, height: 200)) {
                    Color.clear
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                AvatarView(account: account, size: .large)
                    .overlay(Circle().strokeBorder(.background, lineWidth: 3))
                    .padding(.leading, 12)
                    .offset(y: 26)
            }
            .padding(.bottom, 30)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var stats: some View {
        stat(account.statusesCount, "Posts")
        stat(account.followingCount, "Following")
        stat(account.followersCount, "Followers")
    }

    @ViewBuilder
    private func stat(_ value: Int?, _ label: String) -> some View {
        if let value {
            HStack(spacing: 4) {
                Text(value, format: .number.notation(.compactName))
                    .fontWeight(.semibold)
                Text(label)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

#Preview {
    AccountView(account: .preview)
        .previewEnvironment()
}
