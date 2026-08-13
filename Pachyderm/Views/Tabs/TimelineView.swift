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
    @Environment(StreamingCenter.self) private var streaming
    @Environment(\.scenePhase) private var scenePhase

    /// The app keeps this selection for the next start. A start on a different
    /// timeline is an unwanted result for the user.
    @AppStorage("selectedTimeline") private var timeline: Mastodon.Timeline = .home

    @State private var model: PagedListModel<Mastodon.Status>?
    @State private var isComposing = false

    /// The socket of the local and the federated timeline. The home timeline
    /// rides on the shared `user` socket instead, because that one channel also
    /// feeds the notifications, the messages and the badge.
    @State private var publicMonitor: MastodonStreamMonitor?
    @State private var publicKind: Mastodon.StreamKind?

    private static let handlerID = "TimelineView"

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
                Button("New Post", systemImage: "square.and.pencil") {
                    isComposing = true
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
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
                AccountMenu()
            }
        }
        .sheet(isPresented: $isComposing) {
            ComposeView { created in
                model?.prepend(created)
            }
            .presentationCompactAdaptation(horizontal: .fullScreenCover, vertical: .popover)
            .presentationBackground(Color(UIColor.systemBackground))
        }
        .task {
            let model = model ?? PagedListModel(source: source(for: timeline))
            self.model = model
            observe(timeline, model: model)
        }
        .onChange(of: timeline) { _, newValue in
            guard let model else { return }
            model.replaceSource(source(for: newValue))
            observe(newValue, model: model)
        }
        .onChange(of: scenePhase) { oldValue, newValue in
            guard let model else { return }
            switch newValue {
            case .active:
                observe(timeline, model: model)
                // The socket of a public timeline carried nothing while the app
                // slept, and it reports no reconnection because it is new. One
                // page fills the gap. The shared socket does this on its own.
                if oldValue == .background, publicMonitor != nil {
                    Task { await model.refresh() }
                }
            case .background:
                stopPublicMonitor()
            default:
                break
            }
        }
    }

    private func source(for timeline: Mastodon.Timeline) -> PagedListModel<Mastodon.Status>.Source {
        let api = api
        return { olderThan in
            try await api.statuses(in: timeline, olderThan: olderThan)
        }
    }

    // MARK: - Live updates

    /// Points the view at the channel of the timeline on the screen.
    ///
    /// The call is safe more than one time. A registration under the same id
    /// replaces the earlier one, thus a change of the timeline leaves no second
    /// handler behind.
    private func observe(_ timeline: Mastodon.Timeline, model: PagedListModel<Mastodon.Status>) {
        guard api.supportsStreaming, let kind = Mastodon.StreamKind(timeline: timeline) else {
            // The bubble timeline of Akkoma has no channel, thus it stays on
            // pull to refresh.
            streaming.removeHandler(Self.handlerID)
            stopPublicMonitor()
            return
        }

        guard kind != .user else {
            stopPublicMonitor()
            streaming.addHandler(Self.handlerID, onReconnect: { await model.refresh() }) { event in
                await Self.apply(event, to: model)
            }
            return
        }

        streaming.removeHandler(Self.handlerID)
        guard scenePhase == .active else { return }

        // A socket on the right channel stays. The app comes back from the
        // notification centre through the active phase too, and a working
        // socket must survive that.
        if let publicMonitor, publicMonitor.isRunning, publicKind == kind { return }

        stopPublicMonitor()
        let monitor = MastodonStreamMonitor(streaming: api.streaming(), kind: kind)
        monitor.onReconnect = { await model.refresh() }
        monitor.start { event in await Self.apply(event, to: model) }
        publicMonitor = monitor
        publicKind = kind
    }

    private func stopPublicMonitor() {
        publicMonitor?.stop()
        publicMonitor = nil
        publicKind = nil
    }

    private static func apply(
        _ event: Mastodon.StreamEvent,
        to model: PagedListModel<Mastodon.Status>
    ) async {
        switch event {
        case .update(let status):
            await model.receive(status)
        case .statusUpdate(let status):
            model.replace(status)
        case .delete(let id):
            model.remove(id: id)
        case .notification, .conversation, .filtersChanged:
            break
        }
    }
}

#Preview {
    TimelineView()
        .previewEnvironment()
}
