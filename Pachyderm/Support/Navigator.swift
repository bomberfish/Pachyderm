//
//  Navigator.swift
//  Pachyderm
//

import Observation
import SwiftUI

/// The stack of screens for one tab.
///
/// A cell asks the navigator for a post screen or an account screen. The cell is
/// not in a `NavigationLink` view. Thus the links in the text of the post and
/// the action buttons operate correctly. A `NavigationLink` view takes all the
/// touch events of its content. The earlier cell put one link in a different
/// link: a link for the row and a link for the author. Two links in this
/// arrangement have no defined result.
@MainActor
@Observable
final class Navigator {
    var path = NavigationPath()

    /// Shows the detail screen for a post. For a boost it shows the original
    /// post.
    func open(_ status: Mastodon.Status) {
        path.append(status.displayed)
    }

    func open(_ account: Mastodon.Account) {
        path.append(account)
    }

    func popToRoot() {
        path = NavigationPath()
    }
}

/// A `NavigationStack` view that can show the Mastodon types.
///
/// Each tab uses this view. Thus the `navigationDestination` modifiers are in
/// one place. They are not in each screen.
struct MastodonNavigationStack<Content: View>: View {
    @State private var navigator = Navigator()

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        NavigationStack(path: $navigator.path) {
            content
                .navigationDestination(for: Mastodon.Status.self) { status in
                    PostDetailView(status: status)
                }
                .navigationDestination(for: Mastodon.Account.self) { account in
                    AccountView(account: account)
                }
        }
        .environment(navigator)
    }
}

extension View {
    /// The large title and the account button at the root of each tab.
    ///
    /// The earlier code had a copy of this modifier in four views. Each copy
    /// also had an `#available` test for `sharedBackgroundVisibility`.
    func tabToolbar(_ title: String) -> some View {
        modifier(TabToolbarModifier(title: title))
    }
}

private struct TabToolbarModifier: ViewModifier {
    let title: String

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    AccountMenu()
                }
            }
    }
}
