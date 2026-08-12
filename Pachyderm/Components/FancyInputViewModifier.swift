// bomberfish
// FancyInputViewModifier.swift – Picasso
// created on 2023-12-08

import SwiftUI

public struct FancyInputViewModifier: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .textEditorStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .glassBackport(.regular(nil, true), in: Capsule())
    }
}

extension View {
    /// A short form of `.modifier(FancyInputViewModifier())`.
    func fancyInput() -> some View {
        modifier(FancyInputViewModifier())
    }
}
