//
//  SearchView.swift
//  Pachyderm
//
//  Created by Hariz Shirazi on 2025-06-13.
//

import SwiftUI

/// The search tab. The earlier screen showed the text of the user only.
struct SearchView: View {
    @Binding var query: String

    @Environment(MastoAPI.self) private var api
    @Environment(Navigator.self) private var navigator

    @State private var results: Mastodon.SearchResults?
    @State private var isSearching = false
    @State private var failure: String?

    var body: some View {
        List {
            if let results {
                if !results.accounts.isEmpty {
                    Section("People") {
                        ForEach(results.accounts) { account in
                            Button {
                                navigator.open(account)
                            } label: {
                                accountRow(account)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !results.hashtags.isEmpty {
                    Section("Hashtags") {
                        ForEach(results.hashtags) { tag in
                            if let url = URL(string: tag.url ?? "") {
                                Link(destination: url) {
                                    Label("#\(tag.name)", systemImage: "number")
                                }
                            } else {
                                Label("#\(tag.name)", systemImage: "number")
                            }
                        }
                    }
                }

                if !results.statuses.isEmpty {
                    Section("Posts") {
                        ForEach(results.statuses) { status in
                            PostCell(status: .constant(status), showsActions: false)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .tabToolbar("Search")
        // The search field belongs to this screen, not to the `TabView`. A
        // field on the `TabView` gives a persistent field in the navigation bar
        // of each tab, because these screens set an inline title. iOS 26 and
        // later still lift this field into the tab bar. Look at `MainView`.
        .searchable(text: $query, prompt: "Search posts, users, hashtags")
        .overlay { placeholder }
        // The task starts again after each change of the text. The sleep
        // operation gives a delay. The system stops the previous task before
        // that delay ends.
        .task(id: query) { await search() }
    }

    @ViewBuilder
    private var placeholder: some View {
        if isSearching {
            ProgressView()
        } else if let failure {
            ContentUnavailableView {
                Label("Search Failed", systemImage: "exclamationmark.triangle")
            } description: {
                Text(failure)
            }
        } else if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView(
                "Search",
                systemImage: "magnifyingglass",
                description: Text("Find people, posts and hashtags.")
            )
        } else if results?.isEmpty ?? false {
            ContentUnavailableView.search(text: query)
        }
    }

    private func accountRow(_ account: Mastodon.Account) -> some View {
        HStack(spacing: 10) {
            AvatarView(account: account, size: .small)
            VStack(alignment: .leading, spacing: 1) {
                RichText(html: account.bestDisplayName, emoji: account.emojis)
                    .font(.headline)
                    .lineLimit(1)
                Text(verbatim: "@\(account.acct)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = nil
            failure = nil
            return
        }

        do {
            try await Task.sleep(for: .milliseconds(350))
            isSearching = true
            defer { isSearching = false }
            let found = try await api.search(trimmed)
            guard !Task.isCancelled else { return }
            results = found
            failure = nil
        } catch is CancellationError {
            // The next key of the user replaces this search.
        } catch {
            failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

#Preview {
    SearchView(query: .constant(""))
        .previewEnvironment()
}
