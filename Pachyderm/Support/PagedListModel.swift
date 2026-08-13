//
//  PagedListModel.swift
//  Pachyderm
//

import Foundation
import Observation
import os

/// The page state of one list from the API.
///
/// The timeline screen, the profile screen and the notification screen each had
/// their own load code, refresh code and load-more code. All three copies had
/// the same three defects. Two requests at the same time made two copies of a
/// row. An unsuccessful load left an activity indicator on the screen for all
/// time. At the end of a feed the screen continued to send requests.
///
/// The class is generic. Thus posts, notifications and conversations can use
/// it.
@MainActor
@Observable
final class PagedListModel<Item: Identifiable & Sendable & RichContentSource> where Item.ID == String {
    /// Gets one page. The `olderThan` value is the id of the last item on the
    /// screen. It is nil for the first page. The closure is `@MainActor`,
    /// because it holds the client.
    typealias Source = @MainActor (_ olderThan: String?) async throws -> [Item]

    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    /// The property is not read-only. Thus `ForEach($model.items)` can give a
    /// binding to each row. A favourite operation or a boost operation then
    /// changes only that row. The list does not load again.
    var items: [Item] = []

    /// The items that arrived from the stream and wait for the reader.
    ///
    /// A streamed item must not go straight into `items`. The list is a
    /// `LazyVStack` view inside a `ScrollView` view, thus an insertion at the
    /// top moves each row below it. The text under the thumb of a reader would
    /// change while they read it. The count goes onto a button instead, and the
    /// reader chooses the moment.
    private(set) var pending: [Item] = []

    private(set) var phase: Phase = .idle
    private(set) var isLoadingMore = false
    /// False after the server sends a page with less items than the page size.
    /// A subsequent request gives no more items.
    private(set) var hasMore = true

    private let pageSize: Int
    private var source: Source
    private var task: Task<Void, Never>?
    private var seenIDs = Set<String>()

    init(pageSize: Int = 40, source: @escaping Source) {
        self.pageSize = pageSize
        self.source = source
    }

    var isEmpty: Bool { items.isEmpty }

    var pendingCount: Int { pending.count }

    /// Changes the feed and loads it. An example is a change from Home to
    /// Federated.
    func replaceSource(_ source: @escaping Source) {
        self.source = source
        task?.cancel()
        items = []
        pending = []
        seenIDs = []
        hasMore = true
        phase = .idle
        load()
    }

    /// The first load. A `.task` modifier can call it at each appearance. The
    /// function does nothing when the list has content.
    func loadIfNeeded() {
        guard phase == .idle else { return }
        load()
    }

    func load() {
        task?.cancel()
        phase = .loading
        task = Task { [weak self] in
            await self?.fetchFirstPage()
        }
    }

    /// The pull-to-refresh function. It is `async`. Thus SwiftUI keeps the
    /// activity indicator on the screen until the load operation ends.
    func refresh() async {
        task?.cancel()
        task = Task { [weak self] in
            await self?.fetchFirstPage()
        }
        await task?.value
    }

    func loadMore() {
        guard hasMore, !isLoadingMore, phase == .loaded, let last = items.last else { return }

        isLoadingMore = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.isLoadingMore = false }
            do {
                let page = try await self.source(last.id)
                guard !Task.isCancelled else { return }
                await self.append(page)
            } catch is CancellationError {
                // The user scrolled away. Report nothing.
            } catch {
                // Keep the items on the screen. But do not send a new request
                // at each scroll movement.
                self.hasMore = false
                Log.ui.error("Loading another page failed: \(error.localizedDescription)")
            }
        }
    }

    /// Puts a new item at the top. A new post of the user is an example.
    ///
    /// The item goes onto the screen at once. It does not go into `pending`,
    /// because the reader made this item and expects to see it.
    func prepend(_ item: Item) {
        guard seenIDs.insert(item.id).inserted else { return }
        items.insert(item, at: 0)
    }

    // MARK: - Live updates

    /// Takes one item from the stream into the buffer.
    ///
    /// The id enters `seenIDs` at the flush operation and not here. A page from
    /// `loadMore` can hold the same item, and the buffer must not hide it.
    func receive(_ item: Item) async {
        guard !holds(item.id) else { return }
        // Make the rich text before the row reaches the screen, as a page does.
        await RichContentCache.shared.warm(item.richContentPieces)
        guard !Task.isCancelled, !holds(item.id) else { return }
        pending.append(item)
    }

    /// Moves the buffer onto the screen, newest first.
    func flushPending() {
        guard !pending.isEmpty else { return }
        let fresh = pending.filter { seenIDs.insert($0.id).inserted }
        pending = []
        items.insert(contentsOf: fresh.reversed(), at: 0)
    }

    /// Takes an item off the screen. A `delete` event calls it.
    func remove(id: String) {
        items.removeAll { $0.id == id }
        pending.removeAll { $0.id == id }
        seenIDs.remove(id)
    }

    /// Empties the screen. A "clear all" command calls it.
    func removeAll() {
        items = []
        pending = []
        seenIDs = []
    }

    /// Exchanges one item in place. An edit of a post calls it.
    ///
    /// The function does nothing when the item is on neither list. An edit of an
    /// item that the reader never had is not news, and an insertion of it here
    /// would put it in the wrong place in the order.
    func replace(_ item: Item) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else if let index = pending.firstIndex(where: { $0.id == item.id }) {
            pending[index] = item
        }
    }

    /// True when the item is on the screen or in the buffer.
    private func holds(_ id: String) -> Bool {
        seenIDs.contains(id) || pending.contains { $0.id == id }
    }

    // MARK: - Private

    private func fetchFirstPage() async {
        do {
            let page = try await source(nil)
            guard !Task.isCancelled else { return }
            items = []
            // This page holds each item that the buffer held, and it holds them
            // in the correct order.
            pending = []
            seenIDs = []
            await append(page)
            phase = .loaded
        } catch is CancellationError {
            // A newer load operation replaced this one. That operation sets
            // the phase.
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// Adds the new items. It removes an item that is on the screen.
    ///
    /// Two pages contain the same item when a person makes a post during the
    /// scroll movement. Two equal ids in a `ForEach` view make SwiftUI remove
    /// rows and write warnings.
    ///
    /// The HTML of the whole page becomes rich text before the items reach the
    /// screen. That work happens off the main actor, thus a row does not read
    /// its own HTML during the first layout pass.
    private func append(_ page: [Item]) async {
        let fresh = page.filter { seenIDs.insert($0.id).inserted }
        await RichContentCache.shared.warm(fresh.flatMap(\.richContentPieces))
        guard !Task.isCancelled else { return }
        items.append(contentsOf: fresh)
        hasMore = page.count >= pageSize
    }
}
