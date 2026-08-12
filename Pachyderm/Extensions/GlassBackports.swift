//
//  ButtonStyle+glassBackport.swift
//  Sasquatch
//
//  Created on 2026-06-23.
//

import SwiftUI

struct GlassBackportButtonStyle: PrimitiveButtonStyle {
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let button = Button(role: configuration.role) {
            configuration.trigger()
        } label: {
            configuration.label
        }

        if #available(iOS 19.0, *) {
            if prominent {
                button.buttonStyle(GlassProminentButtonStyle())
            } else {
                button.buttonStyle(GlassButtonStyle())
            }
        } else {
            if prominent {
                button.buttonStyle(BorderedProminentButtonStyle())
            } else {
                button.buttonStyle(BorderedButtonStyle())
            }
        }
    }
}

extension PrimitiveButtonStyle where Self == GlassBackportButtonStyle {
    /// A button style that applies border artwork based on the button's context,
    /// enabling a glass effect on compatible platforms.
    static var glassBackport: GlassBackportButtonStyle { GlassBackportButtonStyle() }

    /// A prominent button style that applies border artwork based on the
    /// button's context, enabling a glass effect on compatible platforms.
    static var glassBackportProminent: GlassBackportButtonStyle {
        GlassBackportButtonStyle(prominent: true)
    }
}

struct GlassEffectBackport<S: Shape>: ViewModifier {
    var glass: GlassBackport
    var clipShape: S
    func body(content: Content) -> some View {
        
        if #available(iOS 19.0, *) {
            content.glassEffect(glass.toSystemGlass(), in: clipShape)
        } else {
            content
                .background(glass.toMaterialView().clipShape(clipShape))
        }
    }
}

struct GlassEffectIDBackport<ID: Hashable & Sendable>: ViewModifier {
    var id: ID
    var ns: Namespace.ID
    func body(content: Content) -> some View {
        
        if #available(iOS 19.0, *) {
            content.glassEffectID(id, in: ns)
        } else {
            content
        }
    }
}

extension View {
    func glassBackport(_ glass: GlassBackport = .regular(nil, true), in shape: some Shape = Capsule()) -> some View {
        modifier(GlassEffectBackport(glass: glass, clipShape: shape))
    }
    public func glassBackportID(_ id: (some Hashable & Sendable)?, in namespace: Namespace.ID) -> some View {
        modifier(GlassEffectIDBackport(id: id, ns: namespace))
    }
}

public enum GlassBackport{
    case regular(Color?, Bool),clear(Color?, Bool),identity(Color?, Bool)
    
    @available(iOS 19.0, *)
    func toSystemGlass() -> Glass {
        switch self {
        case .regular(let t, let i):
            .regular.tint(t).interactive(i)
        case .clear(let t, let i):
            .clear.tint(t).interactive(i)
        case .identity(let t, let i):
            .identity.tint(t).interactive(i)
        }
    }
    
    func toMaterialView() -> some View {
        Group {
            switch self {
            case .regular(let t, _):
                ZStack {
                    Rectangle().fill(.regularMaterial)
                    if let t {
                        t.opacity(0.3)
                    }
                }
            case .clear(let t, _):
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    if let t {
                        t.opacity(0.2)
                    }
                }
            case .identity(_, _):
                Rectangle().fill(.clear)
            }
        }
    }
}

struct GlassEffectBackportContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if #available(iOS 19.0, *) {
            GlassEffectContainer {
                content
            }
        } else {
            content
        }
    }
}

