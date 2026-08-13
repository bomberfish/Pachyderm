//
//  RootView.swift
//  Pachyderm
//
//  Created by Hariz Shirazi on 2025-06-12.
//

import SwiftUI

struct RootView: View {
    @Environment(MastoAPI.self) private var api
    @Environment(StreamingCenter.self) private var streaming

    var body: some View {
        Group {
            if api.isAuthenticated {
                MainView()
            } else {
                SetupView()
            }
        }
        .animation(.default, value: api.isAuthenticated)
        // A sign-out leaves a socket that carries a dead token, and it would
        // then reconnect for ever. A change of the account leaves one that
        // carries the posts of the other account.
        .onChange(of: api.credentials) { _, credentials in
            if credentials.isAuthenticated {
                streaming.start()
            } else {
                streaming.stop()
            }
        }
    }
}

struct MainView: View {
    @Environment(MastoAPI.self) private var api
    @Environment(ErrorPresenter.self) private var errors
    @Environment(StreamingCenter.self) private var streaming
    @Environment(\.scenePhase) private var scenePhase

    @State private var searchQuery = ""
    @State private var unreadNotifications: Int = 0

    private static let handlerID = "MainView"

    
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
            .badge(unreadNotifications)
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
        .task {
            await api.refreshInstanceIfNeeded()
            // The instance names its own streaming address. The socket opens
            // before this request lands, thus this second call gives it the
            // chance to move to that address.
            streaming.start()
        }
        .task {
            // The badge counts the notifications that arrive while the user
            // looks at another tab.
            streaming.addHandler(
                Self.handlerID,
                onReconnect: {
                    unreadNotifications = (try? await api.unreadNotificationCount().count) ?? 0
                }
            ) { event in
                guard case .notification = event else { return }
                unreadNotifications += 1
            }
            streaming.start()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                streaming.start()
            case .background:
                // iOS suspends the app and closes the socket anyway. An
                // explicit close costs no battery and gives a known state.
                streaming.stop()
            default:
                break
            }
        }
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
            unreadNotifications = (try? await api.unreadNotificationCount().count) ?? 0
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
    let api = MastoAPI(credentials: MastodonCredentials(host: "mastodon.social", accessToken: nil))
    RootView()
        .environment(api)
        .environment(ErrorPresenter())
        .environment(StreamingCenter(api: api))
}
