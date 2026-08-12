//
//  PostDetailView.swift
//  Pachyderm
//
//  Created by Hariz Shirazi on 2025-06-13.
//

import SwiftUI

/// A post with its thread.
///
/// The screen gets the status as a value. Thus it holds its own copy, and a
/// command on this screen needs no binding to the list. The screen also gets the
/// status and the thread from the server again. Thus a post from a timeline
/// shows the counts of this moment, not the counts from the time of the page
/// request.
struct PostDetailView: View {
    @Environment(MastoAPI.self) private var api
    @Environment(ErrorPresenter.self) private var errors

    @State private var status: Mastodon.Status
    @State private var ancestors: [Mastodon.Status] = []
    @State private var descendants: [Mastodon.Status] = []
    @State private var isLoadingThread = true
    @State private var isComposingReply = false

    init(status: Mastodon.Status) {
        _status = State(initialValue: status.displayed)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach($ancestors) { $ancestor in
                    PostCell(status: $ancestor)
                        .padding(.horizontal)
                    Divider()
                }

                PostCell(status: $status, isDetail: true)
                    .padding(.horizontal)
                    .id(status.id)

                metadata
                    .padding(.horizontal)
                    .padding(.bottom, 8)

                Divider()

                if isLoadingThread {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else if descendants.isEmpty {
                    Text("No replies yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else {
                    ForEach($descendants) { $reply in
                        PostCell(status: $reply)
                            .padding(.leading, 12)
                            .padding(.horizontal)
                        Divider()
                    }
                }
            }
        }
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Reply", systemImage: "arrowshape.turn.up.left") {
                    isComposingReply = true
                }
            }
        }
        .sheet(isPresented: $isComposingReply) {
            ComposeView(inReplyTo: status) { reply in
                descendants.append(reply)
                status.repliesCount += 1
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    /// The data that a timeline row has no space for.
    private var metadata: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let createdAt = status.createdAt {
                Text(createdAt, format: .dateTime.weekday(.abbreviated).day().month().year().hour().minute())
            }
            if let editedAt = status.editedAt {
                Text("Edited \(editedAt, format: .relative(presentation: .named))")
            }
            if let visibility = status.visibility {
                Label(visibility.description, systemImage: visibility.icon)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func load() async {
        do {
            // The request for the thread is the slow request. The app makes the
            // two requests together. Thus the user does not wait for one
            // request and then for the other request.
            async let refreshed = api.status(id: status.id)
            async let context = api.context(of: status.id)

            let (updated, thread) = try await (refreshed, context)
            status = updated
            ancestors = thread.ancestors
            descendants = thread.descendants
        } catch is CancellationError {
            // The user left the screen.
        } catch {
            errors.present(error, title: "Couldn't load the thread")
        }
        isLoadingThread = false
    }
}

#Preview {
    PostDetailView(status: .preview)
        .previewEnvironment()
}
