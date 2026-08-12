//
//  RootView.swift
//  Pachyderm
//
//  Created by Hariz Shirazi on 2025-06-12.
//

import SwiftUI

struct RootView: View {
    @Environment(MastoAPI.self) private var api

    var body: some View {
        Group {
            if api.isAuthenticated {
                MainView()
            } else {
                SetupView()
            }
        }
        .animation(.default, value: api.isAuthenticated)
    }
}

struct MainView: View {
    @Environment(MastoAPI.self) private var api
    @Environment(ErrorPresenter.self) private var errors

    @State private var searchQuery = ""

    var body: some View {
        TabView {
            Tab("Timeline", systemImage: "rectangle.stack") {
                MastodonNavigationStack {
                    if #available(iOS 27.0, *) {
                        TimelineView()
                            .scrollEdgeEffectStyle(.soft, for: .top)
                    } else {
                        TimelineView()
                    }
                }
            }
            Tab("Notifications", systemImage: "bell") {
                MastodonNavigationStack { NotificationsView() }
            }
            Tab("Messages", systemImage: "bubble.left.and.bubble.right") {
                MastodonNavigationStack { MessagesView() }
            }
            Tab(role: .search) {
                MastodonNavigationStack { SearchView(query: $searchQuery) }
            }
        }
        // `SearchView` holds the search field. This modifier lifts that field
        // into the tab bar and opens it when the user selects the search tab.
        .tabViewSearchActivationBackport()
        .tabBarMinimizeBehaviorBackport()
        // This task gets the post limits and the features of the fork. It is a
        // separate task, thus it does not delay the account below. It also
        // reports no error, because the app operates without this data.
        .task { await api.refreshInstanceIfNeeded() }
        .task {
            // The avatar in the toolbar and the compose screen need this data.
            guard api.currentAccount == nil else { return }
            do {
                try await api.refreshCurrentAccount()
            } catch {
                // An old token gives an error here first. Send the user to the
                // sign-in screen. Do not show an empty timeline.
                if (error as? MastodonError)?.requiresReauthentication == true {
                    api.logOut()
                }
                errors.present(error, title: "Couldn't load your account")
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func tabBarMinimizeBehaviorBackport() -> some View {
        if #available(iOS 19.0, *) {
            self.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }

    /// Earlier systems show the search field of `SearchView` in the navigation
    /// bar of the search tab. They do not use the tab bar.
    @ViewBuilder
    func tabViewSearchActivationBackport() -> some View {
        if #available(iOS 19.0, *) {
            self.tabViewSearchActivation(.searchTabSelection)
        } else {
            self
        }
    }
}

#Preview {
    RootView()
        .environment(MastoAPI(credentials: MastodonCredentials(host: "mastodon.social", accessToken: nil)))
        .environment(ErrorPresenter())
}
