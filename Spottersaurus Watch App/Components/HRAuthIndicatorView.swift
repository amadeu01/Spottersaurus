//
//  HRAuthIndicatorView.swift
//  Spottersaurus Watch App
//
//  Compact caution chip explaining a blank HR readout when HealthKit
//  heart-rate read access is denied or hasn't been asked for yet. Renders
//  nothing once authorized so it never crowds the live-set metrics grid.
//

import SwiftUI
import SpottersaurusKit

struct HRAuthIndicatorView: View {
    var status: HealthAuthorizationStatus

    var body: some View {
        switch status {
        case .sharingAuthorized:
            EmptyView()
        case .notDetermined:
            chip(text: "HR not authorized")
        case .sharingDenied:
            chip(text: "Enable HR in Settings")
        }
    }

    private func chip(text: String) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "heart.slash")
                .font(.system(.caption2, weight: .semibold))
            Text(text)
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(Theme.Colors.caution)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(
            Capsule(style: .continuous)
                .fill(Theme.Colors.caution.opacity(0.15))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

#Preview("Authorized") {
    HRAuthIndicatorView(status: .sharingAuthorized)
        .padding()
        .background(Theme.Colors.canvas)
}

#Preview("Not Determined") {
    HRAuthIndicatorView(status: .notDetermined)
        .padding()
        .background(Theme.Colors.canvas)
}

#Preview("Denied") {
    HRAuthIndicatorView(status: .sharingDenied)
        .padding()
        .background(Theme.Colors.canvas)
}
