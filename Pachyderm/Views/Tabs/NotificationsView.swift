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
    @Environment(ErrorPresenter.self) private var errors

    @State private var model: PagedListModel<Mastodon.Notification>?
    @State private var position = ScrollPosition()
    /// The number of notifications, counted from the top, that the highlight
    /// covers.
    @State private var unreadCount = 0

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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear Notifications", systemImage: "checkmark.circle") {
                    clearAll()
                }
                .disabled(model?.isEmpty ?? true)
            }
        }
        .task {
            if model == nil {
                let api = api
                model = PagedListModel { olderThan in
                    try await api.notifications(olderThan: olderThan)
                }
                unreadCount = (try? await api.unreadNotificationCount().count) ?? 0
            }

            // The `user` channel carries the notifications too, thus this screen
            // needs no socket of its own.
            guard let model, api.supportsStreaming else { return }
            streaming.addHandler(
                Self.handlerID,
                onReconnect: {
                    await model.refresh()
                    unreadCount = (try? await api.unreadNotificationCount().count) ?? 0
                }
            ) { event in
                guard case .notification(let notification) = event else { return }
                await model.receive(notification)
                unreadCount += 1
            }
        }
    }

    private func list(_ model: PagedListModel<Mastodon.Notification>) -> some View {
        List {
            ForEach(Array(model.items.enumerated()), id: \.element.id) { index, notification in
                NotificationRow(notification: notification, isUnread: index < unreadCount)
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if index < unreadCount {
                            Button {
                                markAsRead(notification, at: index)
                            } label: {
                                Label("Mark as Read", systemImage: "checkmark.circle")
                            }
                            .tint(.blue)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            delete(notification, at: index)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .listRowInsets(.init())
            }

            if model.phase == .loaded && model.hasMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .onAppear { model.loadMore() }
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollPosition($position)
        .refreshable {
            await model.refresh()
            await markAllAsRead(model)
        }
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

    /// Moves the read marker to `notification`. Everything from it and
    /// further back becomes read; anything newer stays unread.
    private func markAsRead(_ notification: Mastodon.Notification, at index: Int) {
        let api = api
        Task {
            do {
                try await api.markNotificationsAsRead(upTo: notification.id)
                unreadCount = min(unreadCount, index)
            } catch {
                errors.present(error, title: "Couldn't Mark as Read")
            }
        }
    }

    private func delete(_ notification: Mastodon.Notification, at index: Int) {
        let api = api
        guard let model else { return }
        Task {
            do {
                try await api.dismissNotification(id: notification.id)
                model.remove(id: notification.id)
                if index < unreadCount { unreadCount -= 1 }
            } catch {
                errors.present(error, title: "Couldn't Delete Notification")
            }
        }
    }

    private func clearAll() {
        let api = api
        guard let model else { return }
        Task {
            do {
                try await api.clearNotifications()
                model.removeAll()
                unreadCount = 0
            } catch {
                errors.present(error, title: "Couldn't Clear Notifications")
            }
        }
    }

    /// Moves the read marker past the newest notification on the screen.
    /// A refresh calls this, because the reader has just looked at every
    /// notification that arrived.
    private func markAllAsRead(_ model: PagedListModel<Mastodon.Notification>) async {
        guard let newest = model.items.first else { return }
        do {
            try await api.markNotificationsAsRead(upTo: newest.id)
            unreadCount = 0
        } catch {
            errors.present(error, title: "Couldn't Mark Notifications as Read")
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
    var isUnread: Bool = false

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
                    if isUnread {
                        Circle()
                            .fill(.tint)
                            .frame(width: 8, height: 8)
                            .accessibilityLabel("Unread")
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
        .padding(.horizontal, 8)
        .background {
            if isUnread {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.tint.opacity(0.08))
            }
        }
    }
}

#Preview {
    NotificationsView()
        .previewEnvironment()
}
