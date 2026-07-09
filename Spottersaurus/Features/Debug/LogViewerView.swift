//
//  LogViewerView.swift
//  Spottersaurus
//
//  Debug-only screen for reading back the shared NDJSON log file on-device:
//  a category-filterable list of recent lines plus a share sheet to export
//  the raw file (e.g. AirDrop to a Mac for an LLM to read while debugging).
//

import SwiftUI
import SpottersaurusKit

/// Full set of log categories offered in the filter menu. Kept local to the
/// view (rather than making `AppLogCategory` `CaseIterable` in the package)
/// since the public accessor for the shared store is the only package
/// change this feature needs.
private let allLogCategories: [AppLogCategory] = [
    .calibration, .liveSet, .motion, .persistence, .watchLink, .workout
]

struct LogViewerView: View {
    let store: FileLogStore

    @State private var entries: [LogEntry] = []
    @State private var selectedCategory: AppLogCategory?
    @State private var exportURL: URL?
    @State private var isLoading = false

    init(store: FileLogStore = sharedLogStore) {
        self.store = store
    }

    private var filteredEntries: [LogEntry] {
        guard let selectedCategory else { return entries }
        return entries.filter { $0.category == selectedCategory.rawValue }
    }

    var body: some View {
        NavigationStack {
            List {
                if filteredEntries.isEmpty {
                    ContentUnavailableView(
                        "No Log Lines",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text(isLoading ? "Loading…" : "Nothing logged yet for this filter.")
                    )
                } else {
                    ForEach(Array(filteredEntries.enumerated()), id: \.offset) { _, entry in
                        LogEntryRowView(entry: entry)
                    }
                }
            }
            .navigationTitle("Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("All") { selectedCategory = nil }
                        Divider()
                        ForEach(allLogCategories, id: \.self) { category in
                            Button(category.rawValue.capitalized) { selectedCategory = category }
                        }
                    } label: {
                        Label(
                            selectedCategory?.rawValue.capitalized ?? "All",
                            systemImage: "line.3.horizontal.decrease.circle"
                        )
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await load() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .task {
                await load()
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        let raw = await store.readAll()
        let decoder = JSONDecoder()
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: true)
        let parsed: [LogEntry] = lines.compactMap { line in
            guard let data = line.data(using: .utf8) else { return nil }
            return try? decoder.decode(LogEntry.self, from: data)
        }
        entries = Array(parsed.reversed())
        exportURL = await store.exportURL()
    }
}

private struct LogEntryRowView: View {
    var entry: LogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.sm) {
                Text(entry.level.uppercased())
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .foregroundStyle(levelColor)
                Text(entry.category)
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(entry.target)
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Text(entry.ts)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
            Text(entry.message)
                .font(.system(.footnote, design: .monospaced))
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private var levelColor: Color {
        switch entry.level {
        case "error", "fault":
            return Theme.Colors.alert
        case "warning":
            return Theme.Colors.caution
        case "notice":
            return Theme.Colors.optimal
        default:
            return .secondary
        }
    }
}

#Preview {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("LogViewerPreview-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let fileURL = directory.appendingPathComponent("spottersaurus.log")
    let previewStore = FileLogStore(fileURL: fileURL, maxBytes: 512 * 1024)

    let seedEntries: [LogEntry] = [
        LogEntry(ts: "2026-07-08T14:02:11Z", level: "info", category: "workout", target: "watch", message: "session armed lift=bench setIndex=1"),
        LogEntry(ts: "2026-07-08T14:02:45Z", level: "debug", category: "motion", target: "watch", message: "wrist velocity peak=0.42 m/s rep=1"),
        LogEntry(ts: "2026-07-08T14:03:02Z", level: "notice", category: "liveSet", target: "watch", message: "rep completed count=2 tempoMs=1840"),
        LogEntry(ts: "2026-07-08T14:03:20Z", level: "warning", category: "liveSet", target: "watch", message: "grinding nudge fired rep=3 velocityDrop=0.61"),
        LogEntry(ts: "2026-07-08T14:03:41Z", level: "error", category: "watchLink", target: "iphone", message: "session envelope decode failed id=missing"),
        LogEntry(ts: "2026-07-08T14:04:05Z", level: "notice", category: "persistence", target: "iphone", message: "imported workout session id=A1B2C3")
    ]

    Task {
        for entry in seedEntries {
            await previewStore.append(entry)
        }
    }

    return LogViewerView(store: previewStore)
}
