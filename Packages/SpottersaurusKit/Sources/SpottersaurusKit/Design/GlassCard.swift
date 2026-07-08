//
//  GlassCard.swift
//  SpottersaurusKit
//
//  Native port of the web brief's `bg-slate-900/60 backdrop-blur` glass card:
//  a `.continuous` squircle filled with Liquid Glass / `.ultraThinMaterial`
//  and a hairline border. Available as both a `ViewModifier` (`.glassCard()`)
//  for wrapping arbitrary content and a `GlassCard` container view.
//

#if canImport(SwiftUI)
import SwiftUI

/// Applies the Liquid Glass card treatment to any view: `Theme.Spacing.md`
/// padding, an `.ultraThinMaterial`-filled `Theme.Radius.card` squircle, and
/// a subtle hairline border.
public struct GlassCardModifier: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        content
            .padding(Theme.Spacing.md)
            .background(shape.fill(.ultraThinMaterial))
            .overlay(shape.strokeBorder(.white.opacity(0.12), lineWidth: 1))
            .clipShape(shape)
    }
}

public extension View {
    /// Wraps this view in the standard Spottersaurus glass card treatment.
    func glassCard() -> some View {
        modifier(GlassCardModifier())
    }
}

/// A Liquid Glass card container. Equivalent to `.glassCard()` but usable as
/// a standalone view when a container (rather than a modifier) reads better.
public struct GlassCard<Content: View>: View {
    @ViewBuilder public var content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        content()
            .glassCard()
    }
}

#Preview("GlassCard") {
    ZStack {
        Theme.Colors.canvas.ignoresSafeArea()
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Bench Press")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                MetricReadout(label: "Velocity", value: "0.42", unit: "m/s")
            }
        }
        .padding(Theme.Spacing.lg)
    }
}
#endif
