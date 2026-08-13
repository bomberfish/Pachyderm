//
//  NotificationsView.swift
//  Pachyderm
//
//  Created by Hariz Shirazi on 2025-06-13.
//

import SwiftUI

/// The notifications tab.
struct NotificationsView: View {
    @Environment(MastoAPI.self) private var api
    @Environment(StreamingCenter.self) private var streaming

    @State private var model: PagedListModel<Mastodon.Notification>?
    @State private var position = ScrollPosition()

    private static let handlerID = "NotificationsView"

    var body: some View {
        Group {
            if let model {
                list(model)
            } else {
                ProgressView()
            }
        }
        .tabToolbar("Notifications")
        .task {
            if model == nil {
                let api = api
                model = PagedListModel { olderThan in
                    try await api.notifications(olderThan: olderThan)
                }
            }

            // The `user` channel carries the notifications too, thus this screen
            // needs no socket of its own.
            guard let model, api.supportsStreaming else { return }
            streaming.addHandler(Self.handlerID, onReconnect: { await model.refresh() }) { event in
                guard case .notification(let notification) = event else { return }
                await model.receive(notification)
            }
        }
    }

    private func list(_ model: PagedListModel<Mastodon.Notification>) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(model.items) { notification in
                    NotificationRow(notification: notification)
                        .padding(.horizontal)
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
            title: "^[\(model.pendingCount) new notification](inflect: true)"
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
                        "No Notifications",
                        systemImage: "bell",
                        description: Text("Mentions, boosts and follows show up here.")
                    )
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Couldn't Load Notifications", systemImage: "exclamationmark.triangle")
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

/// One notification. It shows the account, the action and the related post.
///
/// The post in the row is a small copy. It is not a cell that accepts a command.
/// The earlier row gave `.constant(status)` to a `PostCell` view with its
/// buttons. Thus a touch on the favourite button caused no movement and sent no
/// request.
struct NotificationRow: View {
    let notification: Mastodon.Notification

    @Environment(Navigator.self) private var navigator

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                navigator.open(notification.account)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: notification.type.icon)
                        .foregroundStyle(.tint)
                        .frame(width: 20)
                    AvatarView(account: notification.account, size: .small)
                    Text(notification.type.summary(for: notification.account))
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    if let createdAt = notification.createdAt {
                        Text(createdAt, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            if let status = notification.status {
                PostCell(status: .constant(status), showsActions: false)
                    .padding(.leading, 28)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 6)
    }
}

#Preview {
    NotificationsView()
        .previewEnvironment()
}
