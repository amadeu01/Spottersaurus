import SwiftUI

struct HistoryMetricLineView: View {
    var label: String
    var value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.system(.body, design: .rounded, weight: .semibold))
    }
}
