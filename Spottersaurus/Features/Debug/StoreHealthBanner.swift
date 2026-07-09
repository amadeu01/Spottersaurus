//
//  StoreHealthBanner.swift
//  Spottersaurus
//
//  Persistent, non-dismissable warning shown across the whole app when the
//  SwiftData store fell back to `.inMemory` (see `resolveModelContainer` in
//  SpottersaurusKit): in that state nothing the lifter does is ever saved to
//  disk, so we never let them forget it. Renders nothing for the healthy
//  `.cloudKit` / `.local` tiers.
//

import SwiftUI
import SpottersaurusKit

/// Top-of-screen banner reflecting the resolved `StoreTier`. Intentionally
/// has no dismiss affordance — it should stay visible for the lifetime of
/// the (unsaved) session.
struct StoreHealthBanner: View {
    let storeTier: StoreTier

    var body: some View {
        if storeTier == .inMemory {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(.body, design: .rounded, weight: .bold))

                Text("Data is NOT being saved — storage unavailable")
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .frame(minHeight: 44)
            .background(
                Theme.Colors.alert
                    .opacity(0.95)
                    .background(.ultraThinMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .padding(.horizontal, Theme.Spacing.sm)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isStaticText)
        }
    }
}

#Preview("In-memory — banner visible") {
    ZStack(alignment: .top) {
        Color(.systemBackground)
            .ignoresSafeArea()
        StoreHealthBanner(storeTier: .inMemory)
            .padding(.top, Theme.Spacing.xs)
    }
}

#Preview("Local — no banner") {
    ZStack(alignment: .top) {
        Color(.systemBackground)
            .ignoresSafeArea()
        StoreHealthBanner(storeTier: .local)
            .padding(.top, Theme.Spacing.xs)
    }
}
