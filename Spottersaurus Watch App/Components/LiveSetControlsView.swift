import SwiftUI
import SpottersaurusKit

/// Live-set controls. In a **release** build the wearer only ever sees
/// Arm / Rack / Rest Done plus the always-present manual `RACK IT` safety
/// bail — real reps are driven by `SpotEngine` off live motion/HR, not a
/// tap. `completeRep`/`flagGrinding` are dev-only conveniences for testing
/// without hardware and compile out entirely in Release via `#if DEBUG`.
struct LiveSetControlsView: View {
    var state: SetLifecycleState
    var arm: () -> Void
    var completeRep: () -> Void
    var flagGrinding: () -> Void
    var rackIt: () -> Void
    var rack: () -> Void
    var finishRest: () -> Void

    #if DEBUG
    @State private var showDevPanel = false
    #endif

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            switch state {
            case .idle, .complete:
                Button(action: arm) {
                    Label("Arm", systemImage: "bolt.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Colors.brandOrange)

            case .armed, .repping:
                liveButtons

            case .racked, .resting:
                Button(action: finishRest) {
                    Label("Rest Done", systemImage: "timer")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Colors.optimal)
            }
        }
        .font(.system(.body, design: .rounded, weight: .bold))
    }

    /// Real controls for `.armed`/`.repping`: reps come from auto-detection.
    /// The wearer can always end the set (`rack`) or force an immediate
    /// `RACK IT` alarm as a manual safety bail — never gated by DEBUG.
    private var liveButtons: some View {
        VStack(spacing: Theme.Spacing.sm) {
            rackItBailButton

            Button(action: rack) {
                Label("Rack", systemImage: "checkmark")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)

            #if DEBUG
            devPanel
            #endif
        }
    }

    /// Always-visible manual safety bail. Fires the same Stage-2 `RACK IT`
    /// path the auto-spotter uses, so a lifter can self-trigger it if the
    /// pipeline misses a hard pin.
    private var rackItBailButton: some View {
        Button(action: rackIt) {
            Label("RACK IT", systemImage: "hand.raised.fill")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.Colors.alert)
    }

    #if DEBUG
    /// Dev-only manual overrides for testing the lifecycle without real
    /// motion/HR hardware. Hidden by default behind a disclosure toggle so
    /// the live-set screen doesn't look "mocked" during normal use, and
    /// compiles out completely in Release.
    private var devPanel: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Button {
                withAnimation { showDevPanel.toggle() }
            } label: {
                Label(
                    showDevPanel ? "Hide DEBUG panel" : "DEBUG panel",
                    systemImage: "ladybug.fill"
                )
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(.gray)

            if showDevPanel {
                VStack(spacing: Theme.Spacing.xs) {
                    Text("DEBUG — manual overrides")
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: Theme.Spacing.sm) {
                        Button(action: completeRep) {
                            Image(systemName: "plus")
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.bordered)

                        Button(action: flagGrinding) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .tint(Theme.Colors.caution)
                    }
                }
                .padding(Theme.Spacing.xs)
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                )
            }
        }
    }
    #endif
}

#Preview("Idle") {
    LiveSetControlsView(
        state: .idle,
        arm: {},
        completeRep: {},
        flagGrinding: {},
        rackIt: {},
        rack: {},
        finishRest: {}
    )
    .padding()
    .background(Theme.Colors.canvas)
}

#Preview("Armed") {
    LiveSetControlsView(
        state: .armed,
        arm: {},
        completeRep: {},
        flagGrinding: {},
        rackIt: {},
        rack: {},
        finishRest: {}
    )
    .padding()
    .background(Theme.Colors.canvas)
}

#Preview("Resting") {
    LiveSetControlsView(
        state: .resting,
        arm: {},
        completeRep: {},
        flagGrinding: {},
        rackIt: {},
        rack: {},
        finishRest: {}
    )
    .padding()
    .background(Theme.Colors.canvas)
}
