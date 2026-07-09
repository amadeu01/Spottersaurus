import SwiftUI
import SpottersaurusKit

struct ReviewView: View {
    @State private var selectedSection: ReviewSection = .history
    @State private var watchMonitor = PhoneWatchSessionMonitor.shared

    var body: some View {
        VStack(spacing: 0) {
            LiveWatchStatusCardView(
                tick: watchMonitor.lastTick,
                receivedAt: watchMonitor.lastTickReceivedAt,
                importMessage: watchMonitor.lastImportMessage,
                connectionStatus: watchMonitor.connectionStatus
            )
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.sm)
            .background(Theme.Colors.canvas.opacity(0.04))

            Picker("Review", selection: $selectedSection) {
                ForEach(ReviewSection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.sm)
            .background(Theme.Colors.canvas.opacity(0.04))

            Group {
                switch selectedSection {
                case .history:
                    HistoryView()
                case .analytics:
                    AnalyticsView()
                }
            }
        }
    }
}

private enum ReviewSection: String, CaseIterable, Identifiable {
    case history
    case analytics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .history: "History"
        case .analytics: "Analytics"
        }
    }
}
