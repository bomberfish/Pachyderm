//
//  PostList.swift
//  Pachyderm
//

import SwiftUI

/// A list of posts that scrolls and gets more pages. The view also shows the
/// load state, the empty state and the error state.
///
/// This view replaces `InfiniteScrollingPostsView`. That view asked each cell if
/// it was the last cell. The test was `post.id == posts.last?.id` in a `.task`
/// modifier on each cell. Thus each new page caused a new calculation for the
/// full list. This view has one view at the bottom of the list. That view asks
/// for the next page when it comes onto the screen.
struct PostList<Header: View>: View {
    let model: PagedListModel<Mastodon.Status>
    private let header: Header

    @State private var position = ScrollPosition()

    init(model: PagedListModel<Mastodon.Status>, @ViewBuilder header: () -> Header) {
        self.model = model
        self.header = header()
    }

    var body: some View {
        @Bindable var model = model

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header

                ForEach($model.items) { $post in
                    PostCell(status: $post)
                        .padding(.horizontal)
                    Divider()
                }

                footer
            }
        }
        .scrollPosition($position)
        .scrollDismissesKeyboard(.immediately)
        .refreshable { await model.refresh() }
        .task { model.loadIfNeeded() }
        .overlay { placeholder }
        .newItemsPill(
            count: model.pendingCount,
            title: "^[\(model.pendingCount) new post](inflect: true)"
        ) {
            withAnimation { model.flushPending() }
            position.scrollTo(edge: .top)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if model.phase == .loaded {
            if model.hasMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    // The request starts when this view comes onto the screen.
                    // Thus the user sees no delay at the bottom of the list.
                    .onAppear { model.loadMore() }
            } else if !model.isEmpty {
                Text("You're all caught up.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            }
        }
    }

    /// The view is above an empty list only. After an unsuccessful request for
    /// one page, the posts on the screen remain.
    @ViewBuilder
    private var placeholder: some View {
        if model.isEmpty {
            switch model.phase {
            case .loading, .idle:
                ProgressView()
            case .loaded:
                ContentUnavailableView(
                    "No Posts",
                    systemImage: "text.bubble",
                    description: Text("There's nothing here yet.")
                )
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't Load Posts", systemImage: "exclamationmark.triangle")
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

extension PostList where Header == EmptyView {
    init(model: PagedListModel<Mastodon.Status>) {
        self.init(model: model) { EmptyView() }
    }
}
