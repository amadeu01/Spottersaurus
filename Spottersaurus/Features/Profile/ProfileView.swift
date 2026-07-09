//
//  ProfileView.swift
//  Spottersaurus
//
//  Phase 0.1 P1: the new Profile screen — body info (latest imported body
//  weight), the same "Training Maxes" editor `MaxesView` renders (via the
//  shared `MaxesEditorSection`), a "Sync with Apple Health" control wired to
//  H3's `HealthSyncService`, and the Debug Logs entry moved here. P2 swaps
//  this in for the Maxes tab in `PlannerTabsView` — not done by this task.
//

import SwiftData
import SwiftUI
import SpottersaurusKit

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BodyWeightEntry.date, order: .reverse) private var bodyWeightEntries: [BodyWeightEntry]

    @State private var healthSync = HealthSyncService()

    private var latestBodyWeight: BodyWeightEntry? { bodyWeightEntries.first }

    var body: some View {
        NavigationStack {
            List {
                bodyInfoSection
                MaxesEditorSection()
                healthSyncSection
                debugSection
            }
            .navigationTitle("Profile")
        }
    }

    private var bodyInfoSection: some View {
        Section("Body Info") {
            if let entry = latestBodyWeight {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack {
                        Text("Body Weight")
                            .font(.system(.body, design: .rounded, weight: .semibold))
                        Spacer()
                        Text("\(entry.kilograms.formatted(.number.precision(.fractionLength(0...1)))) kg")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Text("As of \(entry.date.formatted(date: .abbreviated, time: .omitted)) — kg, from Apple Health")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, Theme.Spacing.xs)
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("No body weight yet")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                    Text("Sync with Apple Health to import your latest weigh-in.")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, Theme.Spacing.xs)
            }
        }
    }

    private var healthSyncSection: some View {
        Section("Apple Health") {
            Button {
                Task { await healthSync.sync(context: modelContext) }
            } label: {
                Label("Sync with Apple Health", systemImage: "heart.fill")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.Colors.brandOrange)
            .disabled(isSyncing)

            HealthSyncStatusRow(status: healthSync.status, lastSyncedAt: healthSync.lastSyncedAt)
        }
    }

    private var debugSection: some View {
        Section {
            NavigationLink {
                LogViewerView()
            } label: {
                Label("Debug Logs", systemImage: "ladybug")
            }
        }
    }

    private var isSyncing: Bool {
        if case .syncing = healthSync.status { return true }
        return false
    }
}

/// The Apple Health sync status readout: an icon + status line, plus (when
/// known) the last successful sync time — kept even while `.failed`, so a
/// stale-but-real prior sync is distinguishable from "never synced".
private struct HealthSyncStatusRow: View {
    var status: HealthSyncStatus
    var lastSyncedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.sm) {
                icon
                Text(statusLine)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(statusTint)
                Spacer()
            }

            if let lastSyncedAt {
                Text("Last synced \(lastSyncedAt.formatted(.relative(presentation: .named)))")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    @ViewBuilder
    private var icon: some View {
        switch status {
        case .idle:
            Image(systemName: "heart.text.square")
                .foregroundStyle(.secondary)
        case .syncing:
            ProgressView()
        case .synced:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.Colors.optimal)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.Colors.alert)
        }
    }

    private var statusLine: String {
        switch status {
        case .idle: "Not synced yet"
        case .syncing: "Syncing…"
        case .synced(let date): "Synced \(date.formatted(.relative(presentation: .named)))"
        case .failed(let message): message
        }
    }

    private var statusTint: Color {
        switch status {
        case .idle, .syncing: .secondary
        case .synced: Theme.Colors.optimal
        case .failed: Theme.Colors.alert
        }
    }
}

#Preview("Profile") {
    ProfileView()
        .modelContainer(PreviewSeed.profileSeededContainer())
}

#Preview("No body weight yet") {
    ProfileView()
        .modelContainer(PreviewSeed.seededContainer())
}

#Preview("Sync status — all states") {
    List {
        HealthSyncStatusRow(status: .idle, lastSyncedAt: nil)
        HealthSyncStatusRow(status: .syncing, lastSyncedAt: nil)
        HealthSyncStatusRow(status: .synced(.now.addingTimeInterval(-120)), lastSyncedAt: .now.addingTimeInterval(-120))
        HealthSyncStatusRow(status: .failed("Authorization denied"), lastSyncedAt: .now.addingTimeInterval(-86_400))
    }
}
