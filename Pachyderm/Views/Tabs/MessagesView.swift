//
//  MessagesView.swift
//  Pachyderm
//
//  Created by Hariz Shirazi on 2025-06-13.
//

import SwiftUI

/// The tab for direct messages. It shows one row for each conversation.
///
/// The earlier screen was a `Text("Hello, World!")` view below a toolbar.
struct MessagesView: View {
    @Environment(MastoAPI.self) private var api
    @Environment(Navigator.self) private var navigator
    @Environment(StreamingCenter.self) private var streaming

    @State private var model: PagedListModel<Mastodon.Conversation>?
    @State private var position = ScrollPosition()

    private static let handlerID = "MessagesView"

    var body: some View {
        Group {
            if let model {
                list(model)
            } else {
                ProgressView()
            }
        }
        .tabToolbar("Messages")
        .task {
            if model == nil {
                let api = api
                model = PagedListModel { olderThan in
                    try await api.conversations(olderThan: olderThan)
                }
            }

            guard let model, api.supportsStreaming else { return }
            streaming.addHandler(Self.handlerID, onReconnect: { await model.refresh() }) { event in
                guard case .conversation(let conversation) = event else { return }
                // A reply moves a conversation that the list already holds, and
                // it marks it unread. The replacement handles that one, and the
                // buffer takes the conversations that are new. Each call ignores
                // the case of the other.
                model.replace(conversation)
                await model.receive(conversation)
            }
        }
    }

    private func list(_ model: PagedListModel<Mastodon.Conversation>) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(model.items) { conversation in
                    ConversationRow(conversation: conversation)
                        .padding(.horizontal)
                        .contentShape(.rect)
                        .onTapGesture {
                            if let status = conversation.lastStatus {
                                navigator.open(status)
                            }
                        }
                    Divider()
                }

                if model.phase == .loaded && model.hasMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .onAppear { model.loadMore() }
                }
            }
        }
        .scrollPosition($position)
        .refreshable { await model.refresh() }
        .task { model.loadIfNeeded() }
        .newItemsPill(
            count: model.pendingCount,
            title: "^[\(model.pendingCount) new message](inflect: true)"
        ) {
            withAnimation { model.flushPending() }
            position.scrollTo(edge: .top)
        }
        .overlay {
            if model.isEmpty {
                switch model.phase {
                case .idle, .loading:
                    ProgressView()
                case .loaded:
                    ContentUnavailableView(
                        "No Messages",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Private mentions show up here.")
                    )
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Couldn't Load Messages", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Try Again") { model.load() }
                            .buttonStyle(.glassBackportProminent)
                    }
                }
            }
        }
    }
}

private struct ConversationRow: View {
    let conversation: Mastodon.Conversation

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let first = conversation.accounts.first {
                AvatarView(account: first, size: .regular)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(conversation.title)
                        .font(.headline)
                        .lineLimit(1)
                    if conversation.unread {
                        Circle()
                            .fill(.tint)
                            .frame(width: 8, height: 8)
                            .accessibilityLabel("Unread")
                    }
                    Spacer(minLength: 0)
                    if let date = conversation.lastStatus?.createdAt {
                        Text(date, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let last = conversation.lastStatus {
                    RichText(html: last.html, emoji: last.emojis)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    MessagesView()
        .previewEnvironment()
}
