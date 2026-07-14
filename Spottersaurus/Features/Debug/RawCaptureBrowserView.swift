//
//  RawCaptureBrowserView.swift
//  Spottersaurus
//
//  Debug-only screen for the raw sensor captures the Watch transfers to the
//  phone (ADR 0008 / PRC-5). Lists them grouped workout → exercise → set
//  (newest first) via `RawSetCaptureStore.workouts()`, and — per capture —
//  re-runs the detection engine (`SpotEngine.replay`, PRC-4) to show reps /
//  events / metrics, exports the raw stream (`RawSetCapture.exportNDJSON` /
//  `exportCSV` / `exportHeartRateCSV`, PRC-1) over a `ShareLink`, and offers a
//  delete. Surfaced from `ProfileView` next to "Debug Logs".
//
//  The view reads its data through an injectable `RawCaptureSource` (closures
//  over `RawSetCaptureStore.shared` in the app; synthetic in previews) so the
//  UI is exercisable without a paired Watch or on-disk captures.
//

import SwiftUI
import SpottersaurusKit

// MARK: - Data source

/// Injection seam over `RawSetCaptureStore`: closures rather than the concrete
/// singleton so the browser can be driven by synthetic data in `#Preview` and
/// unit-style harnesses (mirrors how `LogViewerView` takes a `FileLogStore`).
struct RawCaptureSource {
    var workouts: () -> [CaptureWorkoutGroup]
    var loadCapture: (RawSetCaptureIdentity) -> RawSetCapture?
    var delete: (RawSetCaptureIdentity) -> Void
    var deleteSet: (UUID) -> Void

    /// The on-device source backed by the real receiver store.
    static let live = RawCaptureSource(
        workouts: { RawSetCaptureStore.shared.workouts() },
        loadCapture: { RawSetCaptureStore.shared.loadCapture($0) },
        delete: { RawSetCaptureStore.shared.delete($0) },
        deleteSet: { RawSetCaptureStore.shared.deleteSet($0) }
    )
}

// MARK: - Level 1: workout list

struct RawCaptureBrowserView: View {
    let source: RawCaptureSource

    @State private var workouts: [CaptureWorkoutGroup] = []

    init(source: RawCaptureSource = .live) {
        self.source = source
    }

    var body: some View {
        List {
            if workouts.isEmpty {
                ContentUnavailableView(
                    "No Captures",
                    systemImage: "waveform.path.ecg",
                    description: Text("Raw sensor captures transferred from the Watch appear here. Run a working set with a paired Watch to record one.")
                )
            } else {
                ForEach(workouts, id: \.sessionID) { workout in
                    Section {
                        NavigationLink {
                            CaptureWorkoutDetailView(workout: workout, source: source, onChange: reload)
                        } label: {
                            WorkoutRow(workout: workout)
                        }
                    }
                }
            }
        }
        .navigationTitle("Raw Captures")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    reload()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        workouts = source.workouts()
    }
}

private struct WorkoutRow: View {
    let workout: CaptureWorkoutGroup

    private var setCount: Int {
        workout.exercises.reduce(0) { $0 + $1.sets.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(workout.armedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.system(.body, design: .rounded, weight: .semibold))
            Text(exercisesSummary)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("\(workout.exercises.count) exercise\(workout.exercises.count == 1 ? "" : "s") · \(setCount) set\(setCount == 1 ? "" : "s")")
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private var exercisesSummary: String {
        workout.exercises.map { $0.lift.displayName }.joined(separator: " · ")
    }
}

// MARK: - Level 2: workout → exercises → sets → captures

private struct CaptureWorkoutDetailView: View {
    let workout: CaptureWorkoutGroup
    let source: RawCaptureSource
    let onChange: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(workout.exercises, id: \.lift) { exercise in
                Section(exercise.lift.displayName) {
                    ForEach(exercise.sets, id: \.setID) { set in
                        ForEach(set.captures, id: \.fileName) { identity in
                            NavigationLink {
                                CaptureDetailView(identity: identity, source: source, onDelete: {
                                    onChange()
                                    dismiss()
                                })
                            } label: {
                                CaptureRow(identity: identity)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(workout.armedAt.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CaptureRow: View {
    let identity: RawSetCaptureIdentity

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Set \(identity.setIndex + 1) of \(identity.setCount)")
                .font(.system(.body, design: .rounded, weight: .semibold))
            Text(identity.armedAt.formatted(date: .omitted, time: .standard))
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}

// MARK: - Level 3: capture detail (replay + export + delete)

private struct CaptureDetailView: View {
    let identity: RawSetCaptureIdentity
    let source: RawCaptureSource
    let onDelete: () -> Void

    @State private var capture: RawSetCapture?
    @State private var analysis: SpotAnalysis?
    @State private var exports: ExportBundle?
    @State private var isLoading = true
    @State private var showDeleteConfirm = false

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("Replaying…")
                        Spacer()
                    }
                    .padding(.vertical, Theme.Spacing.md)
                }
            } else if let capture {
                overviewSection(capture)
                if let analysis {
                    resultSection(analysis)
                    repsSection(analysis)
                    eventsSection(analysis)
                }
                markersSection(capture)
            } else {
                Section {
                    ContentUnavailableView(
                        "Capture Unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text("The stored file for this set could not be loaded — it may have been pruned.")
                    )
                }
            }
        }
        .navigationTitle("\(identity.lift.displayName) · Set \(identity.setIndex + 1)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let exports {
                    Menu {
                        ShareLink("Motion NDJSON", item: exports.ndjson)
                        ShareLink("Motion CSV", item: exports.csv)
                        ShareLink("Heart Rate CSV", item: exports.heartRateCSV)
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .confirmationDialog("Delete this capture?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete Capture", role: .destructive) {
                source.delete(identity)
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        }
        .task(id: identity) {
            await loadAndReplay()
        }
    }

    // MARK: Sections

    private func overviewSection(_ capture: RawSetCapture) -> some View {
        Section("Capture") {
            metricRow("Lift", capture.lift.displayName)
            metricRow("Armed", capture.armedAt.formatted(date: .abbreviated, time: .standard))
            metricRow("Duration", formatSeconds(captureDuration(capture)))
            metricRow("Motion samples", capture.motion.count.formatted())
            metricRow("Heart-rate samples", capture.heartRate.count.formatted())
            metricRow("Schema version", capture.schemaVersion.formatted())
        }
    }

    private func resultSection(_ analysis: SpotAnalysis) -> some View {
        Section("Analysis") {
            metricRow("Detection path", analysis.usedVelocityPath ? "Velocity (VBT)" : "Tempo + HR")
            metricRow("Reps detected", analysis.reps.count.formatted())
            metricRow("Spot events", analysis.events.count.formatted())
            let flagged = analysis.reps.filter(\.flaggedStall).count
            let racked = analysis.reps.filter(\.reachedRackIt).count
            metricRow("Flagged stalls", flagged.formatted(), tint: flagged > 0 ? Theme.Colors.caution : nil)
            metricRow("Reached RACK IT", racked.formatted(), tint: racked > 0 ? Theme.Colors.alert : nil)
        }
    }

    @ViewBuilder
    private func repsSection(_ analysis: SpotAnalysis) -> some View {
        if !analysis.reps.isEmpty {
            Section("Reps") {
                ForEach(analysis.reps, id: \.repIndex) { rep in
                    RepResultRow(rep: rep, showsVelocity: analysis.usedVelocityPath)
                }
            }
        }
    }

    @ViewBuilder
    private func eventsSection(_ analysis: SpotAnalysis) -> some View {
        if !analysis.events.isEmpty {
            Section("Events") {
                ForEach(Array(analysis.events.enumerated()), id: \.offset) { _, event in
                    SpotEventRow(event: event)
                }
            }
        }
    }

    @ViewBuilder
    private func markersSection(_ capture: RawSetCapture) -> some View {
        if !capture.markers.isEmpty {
            Section("Markers") {
                ForEach(Array(capture.markers.enumerated()), id: \.offset) { _, marker in
                    HStack {
                        Text(marker.kind.rawValue.capitalized)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        Spacer()
                        Text(formatSeconds(marker.timestamp))
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func metricRow(_ label: String, _ value: String, tint: Color? = nil) -> some View {
        HStack {
            Text(label)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
            Spacer()
            Text(value)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(tint ?? .secondary)
        }
    }

    // MARK: Work

    private func loadAndReplay() async {
        isLoading = true
        defer { isLoading = false }

        guard let loaded = source.loadCapture(identity) else {
            capture = nil
            return
        }
        capture = loaded
        // Replay is pure/CPU-bound over a Sendable capture — hop off the main
        // actor so a large set's motion stream can't jank the UI.
        analysis = await Task.detached(priority: .userInitiated) {
            SpotEngine.replay(loaded)
        }.value
        exports = ExportBundle(capture: loaded)
    }

    private func captureDuration(_ capture: RawSetCapture) -> TimeInterval {
        let lastMotion = capture.motion.last?.timestamp ?? 0
        let lastHR = capture.heartRate.last?.timestamp ?? 0
        let lastMarker = capture.markers.last?.timestamp ?? 0
        return max(lastMotion, lastHR, lastMarker)
    }

    private func formatSeconds(_ seconds: TimeInterval) -> String {
        String(format: "%.2fs", seconds)
    }
}

private struct RepResultRow: View {
    let rep: RepResult
    let showsVelocity: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text("Rep \(rep.repIndex + 1)")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                Spacer()
                if rep.reachedRackIt {
                    badge("RACK IT", tint: Theme.Colors.alert)
                } else if rep.flaggedStall {
                    badge("Grind", tint: Theme.Colors.caution)
                }
            }
            HStack(spacing: Theme.Spacing.md) {
                stat("Tempo", String(format: "%.2fs", rep.concentricSeconds))
                if showsVelocity {
                    stat("Mean", String(format: "%.2f m/s", rep.meanVelocityMS))
                    stat("Peak", String(format: "%.2f m/s", rep.peakVelocityMS))
                }
                stat("Disp", String(format: "%.2f m", rep.displacementM))
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .monospacedDigit()
        }
    }

    private func badge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(.caption2, design: .rounded, weight: .bold))
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 2)
            .background(tint.opacity(0.2), in: Capsule())
            .foregroundStyle(tint)
    }
}

private struct SpotEventRow: View {
    let event: SpotEvent

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(tint)
                Text("Rep \(event.repIndex + 1) · \(event.reason.rawValue)")
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.2fs", event.timestamp))
                    .monospacedDigit()
                Text(String(format: "%.0f%%", event.confidence * 100))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            .font(.system(.caption2, design: .rounded, weight: .semibold))
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private var title: String {
        switch event.kind {
        case .grinding: "Grinding"
        case .rackIt: "RACK IT"
        case .resolved: "Resolved"
        }
    }

    private var icon: String {
        switch event.kind {
        case .grinding: "exclamationmark.triangle.fill"
        case .rackIt: "exclamationmark.octagon.fill"
        case .resolved: "checkmark.circle.fill"
        }
    }

    private var tint: Color {
        switch event.kind {
        case .grinding: Theme.Colors.caution
        case .rackIt: Theme.Colors.alert
        case .resolved: Theme.Colors.optimal
        }
    }
}

// MARK: - Export files

/// Writes the PRC-1 export strings to temp files with meaningful names +
/// extensions so `ShareLink` presents them as proper `.ndjson`/`.csv`
/// documents (rather than a raw text blob).
private struct ExportBundle {
    let ndjson: URL
    let csv: URL
    let heartRateCSV: URL

    init(capture: RawSetCapture) {
        let base = "capture-\(capture.lift.rawValue)-set\(capture.setIndex + 1)-\(capture.setID.uuidString.prefix(8))"
        ndjson = Self.write(capture.exportNDJSON(), name: "\(base).ndjson")
        csv = Self.write(capture.exportCSV(), name: "\(base)-motion.csv")
        heartRateCSV = Self.write(capture.exportHeartRateCSV(), name: "\(base)-hr.csv")
    }

    private static func write(_ contents: String, name: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

// MARK: - Preview

#Preview("Raw Captures") {
    NavigationStack {
        RawCaptureBrowserView(source: .previewSynthetic())
    }
}

extension RawCaptureSource {
    /// A synthetic in-memory source for previews: two workouts, a few lifts,
    /// with generated motion so replay produces real reps/events.
    static func previewSynthetic() -> RawCaptureSource {
        let captures = PreviewCaptureFactory.makeAll()
        let byFile = Dictionary(uniqueKeysWithValues: captures.map { ($0.setID.uuidString + ".plist", $0) })

        let identities: [RawSetCaptureIdentity] = captures.map { capture in
            RawSetCaptureIdentity(
                sessionID: capture.sessionID,
                setID: capture.setID,
                setIndex: capture.setIndex,
                setCount: capture.setCount,
                lift: capture.lift,
                armedAt: capture.armedAt,
                fileName: capture.setID.uuidString + ".plist"
            )
        }

        return RawCaptureSource(
            workouts: { RawSetCaptureIndex(identities).workouts },
            loadCapture: { byFile[$0.fileName] },
            delete: { _ in },
            deleteSet: { _ in }
        )
    }
}

/// Generates synthetic `RawSetCapture`s for previews with a simple rising/
/// falling acceleration profile per rep, so `SpotEngine.replay` segments a few
/// reps rather than an empty analysis.
private enum PreviewCaptureFactory {
    static func makeAll() -> [RawSetCapture] {
        let session1 = UUID()
        let session2 = UUID()
        return [
            make(session: session1, lift: .bench, setIndex: 0, setCount: 3, minutesAgo: 60, reps: 5),
            make(session: session1, lift: .bench, setIndex: 1, setCount: 3, minutesAgo: 58, reps: 4),
            make(session: session1, lift: .deadlift, setIndex: 0, setCount: 2, minutesAgo: 45, reps: 3),
            make(session: session2, lift: .squat, setIndex: 0, setCount: 3, minutesAgo: 1_440, reps: 5)
        ]
    }

    private static func make(
        session: UUID,
        lift: LiftKind,
        setIndex: Int,
        setCount: Int,
        minutesAgo: Int,
        reps: Int
    ) -> RawSetCapture {
        let hz = 50.0
        let repSeconds = 2.0
        var motion: [DeviceMotionSample] = []
        var markers: [CaptureMarker] = [CaptureMarker(timestamp: 0, kind: .armed)]
        var t = 0.0

        // Brief settle before rep 1.
        for _ in 0..<Int(hz) {
            motion.append(sample(t: t, accelY: 0))
            t += 1 / hz
        }
        markers.append(CaptureMarker(timestamp: t, kind: .settling))

        for rep in 0..<reps {
            let steps = Int(repSeconds * hz)
            for step in 0..<steps {
                let phase = Double(step) / Double(steps) * 2 * .pi
                // Eccentric dip then concentric drive.
                let accelY = sin(phase) * 0.6
                motion.append(sample(t: t, accelY: accelY))
                t += 1 / hz
            }
            markers.append(CaptureMarker(timestamp: t, kind: rep == 0 ? .firstRep : .rep))
        }

        markers.append(CaptureMarker(timestamp: t, kind: .racked))
        markers.append(CaptureMarker(timestamp: t + 1, kind: .ended))

        let heartRate: [HRSample] = stride(from: 0.0, to: t, by: 1.0).map {
            HRSample(timestamp: $0, beatsPerMinute: 120 + $0)
        }

        return RawSetCapture(
            sessionID: session,
            setID: UUID(),
            setIndex: setIndex,
            setCount: setCount,
            lift: lift,
            armedAt: Date().addingTimeInterval(TimeInterval(-minutesAgo * 60)),
            motion: motion,
            heartRate: heartRate,
            markers: markers
        )
    }

    private static func sample(t: TimeInterval, accelY: Double) -> DeviceMotionSample {
        DeviceMotionSample(
            timestamp: t,
            userAccelerationG: Vector3(x: 0, y: accelY, z: 0),
            gravityG: Vector3(x: 0, y: -1, z: 0),
            rotationRateRadS: Vector3(x: 0, y: 0, z: 0),
            attitude: Quaternion(w: 1, x: 0, y: 0, z: 0)
        )
    }
}
