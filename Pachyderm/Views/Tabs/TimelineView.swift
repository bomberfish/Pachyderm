//
//  TimelineView.swift
//  Pachyderm
//
//  Created by Hariz Shirazi on 2025-06-12.
//

import SwiftUI

/// The home tab. It shows one timeline, and it opens the compose screen.
struct TimelineView: View {
    @Environment(MastoAPI.self) private var api

    /// The app keeps this selection for the next start. A start on a different
    /// timeline is an unwanted result for the user.
    @AppStorage("selectedTimeline") private var timeline: Mastodon.Timeline = .home

    @State private var model: PagedListModel<Mastodon.Status>?
    @State private var isComposing = false

    var body: some View {
        Group {
            if let model {
                PostList(model: model)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(timeline.description)
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("Timeline", selection: $timeline) {
                        ForEach(Mastodon.Timeline.validCases(api)) { option in
                            Label(option.description, systemImage: option.icon).tag(option)
                        }
                    }
                } label: {
                    Label("Timeline", systemImage: timeline.icon)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("New Post", systemImage: "square.and.pencil") {
                    isComposing = true
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                AccountMenu()
            }
        }
        .sheet(isPresented: $isComposing) {
            ComposeView { created in
                model?.prepend(created)
            }
        }
        .task {
            if model == nil {
                model = PagedListModel(source: source(for: timeline))
            }
        }
        .onChange(of: timeline) { _, newValue in
            model?.replaceSource(source(for: newValue))
        }
    }

    private func source(for timeline: Mastodon.Timeline) -> PagedListModel<Mastodon.Status>.Source {
        let api = api
        return { olderThan in
            try await api.statuses(in: timeline, olderThan: olderThan)
        }
    }
}

#Preview {
    TimelineView()
        .previewEnvironment()
}
