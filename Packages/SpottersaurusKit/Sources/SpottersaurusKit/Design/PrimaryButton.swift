//
//  PrimaryButton.swift
//  SpottersaurusKit
//
//  Native port of the web brief's primary action buttons
//  (`active:scale-95`, `transition-all`): a `.continuous` squircle filled
//  with the brand tint, a press-scale animation, and a `.sensoryFeedback`
//  tap. Exposed as a `ButtonStyle` for use on any `Button`, plus a
//  convenience `PrimaryButton` view for the common title (+ icon) case.
//

#if canImport(SwiftUI)
import SwiftUI

/// The primary action button style: brand-tinted `.continuous` squircle,
/// 44pt minimum height, press-scale feedback, and a haptic tap.
public struct PrimaryButtonStyle: ButtonStyle {
    /// Fill color. Defaults to the brand accent (safety orange).
    public var tint: Color

    public init(tint: Color = Theme.Colors.brandOrange) {
        self.tint = tint
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded, weight: .bold))
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, Theme.Spacing.md)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(tint)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            // Fire once per completed tap (on release), not on press-down too.
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { wasPressed, isPressed in
                wasPressed && !isPressed
            }
    }
}

/// Convenience primary-action button: title (+ optional SF Symbol) styled
/// with `PrimaryButtonStyle`.
public struct PrimaryButton: View {
    public var title: String
    public var systemImage: String?
    public var tint: Color
    public var action: () -> Void

    public init(
        _ title: String,
        systemImage: String? = nil,
        tint: Color = Theme.Colors.brandOrange,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .buttonStyle(PrimaryButtonStyle(tint: tint))
    }
}

#Preview("PrimaryButton") {
    ZStack {
        Theme.Colors.canvas.ignoresSafeArea()
        VStack(spacing: Theme.Spacing.md) {
            PrimaryButton("Arm Set", systemImage: "bolt.fill") {}
            PrimaryButton("Rack It", tint: Theme.Colors.alert) {}
        }
        .padding(Theme.Spacing.lg)
    }
}
#endif
