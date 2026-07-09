import SwiftData
import SwiftUI
import SpottersaurusKit

/// The standalone Maxes tab. P2 removes this from `PlannerTabsView` (Profile
/// absorbs it), but it's kept working/compiling until that swap lands —
/// content lives in `MaxesEditorSection` so both screens render identically.
struct MaxesView: View {
    var body: some View {
        NavigationStack {
            List {
                MaxesEditorSection()
            }
            .navigationTitle("Maxes")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        LogViewerView()
                    } label: {
                        Label("Debug Logs", systemImage: "ladybug")
                    }
                }
            }
        }
    }
}

#Preview {
    MaxesView()
        .modelContainer(PreviewSeed.seededContainer())
}
