import SwiftUI

struct MetricLine: View {
    var label: String
    var value: Double

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(value.formatted(.number.precision(.fractionLength(0...1)))) kg")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.system(.body, design: .rounded, weight: .semibold))
    }
}
