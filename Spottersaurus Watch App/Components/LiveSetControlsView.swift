import SwiftUI
import SpottersaurusKit

/// Live-set controls. Per ADR 0005 ("No mid-rep manual input"), the wearer's
/// hands are locked on the bar for the entire working set, so the only
/// hands-free live interactions are Start (`arm`) and End (`rack`) — there is
/// no manual grind/rack-it bail, and no manual rep-count nudge in a release
/// build. Real reps and escalations are driven entirely by `SpotEngine` off
/// live motion/HR. `completeRep` is a dev-only convenience for testing
/// without hardware and compiles out entirely in Release via `#if DEBUG`.
struct LiveSetControlsView: View {
    var state: SetLifecycleState
    var arm: () -> Void
    var completeRep: () -> Void
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

            case .settling, .repping:
                liveButtons

            case .racked, .resting:
                Button(action: finishRest) {
                    Label("Rest Done", systemImage: "timer")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Colors.optimal)
            }
        }
        .font(.system(.body, design: .rounded, weight: .bold))
    }

    /// Real controls for `.settling`/`.repping`: reps and any grind/RACK IT
    /// escalation come entirely from auto-detection. The wearer can always
    /// end the set (`rack`) — that's the ADR 0005 "End" hands-free moment,
    /// not a mid-rep input.
    private var liveButtons: some View {
        VStack(spacing: Theme.Spacing.sm) {
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

    #if DEBUG
    /// Dev-only manual override for testing rep counting without real
    /// motion/HR hardware. Hidden by default behind a disclosure toggle so
    /// the live-set screen doesn't look "mocked" during normal use, and
    /// compiles out completely in Release. Deliberately does NOT expose a
    /// grind/RACK IT trigger here — those are live spotter escalations, and
    /// ADR 0005 rules out any mid-rep manual input, dev panel included.
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

                    Button(action: completeRep) {
                        Image(systemName: "plus")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
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
        rack: {},
        finishRest: {}
    )
    .padding()
    .background(Theme.Colors.canvas)
}

#Preview("Settling") {
    LiveSetControlsView(
        state: .settling,
        arm: {},
        completeRep: {},
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
        rack: {},
        finishRest: {}
    )
    .padding()
    .background(Theme.Colors.canvas)
}
