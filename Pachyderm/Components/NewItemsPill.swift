//
//  NewItemsPill.swift
//  Pachyderm
//

import SwiftUI

/// The button that tells the reader how much the stream holds.
///
/// The lists keep each streamed item in a buffer, and this button empties it.
/// A list that grew on its own would move the post under the thumb of the
/// reader, because a `LazyVStack` measures a new row at the top and pushes
/// everything below it down.
struct NewItemsPill: View {
    /// The call site owns the wording, thus each list inflects its own noun.
    /// A noun that arrives through a variable makes `^[...](inflect: true)`
    /// guess, and the guess is wrong for many languages.
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Label(title, systemImage: "arrow.up")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .glassBackport(.clear(nil, true))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        .padding(.top, 8)
    }
}

extension View {
    /// Puts the pill above the list.
    ///
    /// The pill sits in an overlay and not in a safe area inset. An inset
    /// changes the safe area of the scroll view, and the content below it
    /// moves. The whole point of the buffer is that nothing moves.
    func newItemsPill(
        count: Int,
        title: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        overlay(alignment: .top) {
            if count > 0 {
                NewItemsPill(title: title, action: action)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: count > 0)
    }
}

#Preview {
    Color.clear
        .newItemsPill(count: 3, title: "^[3 new posts](inflect: true)") {}
}
