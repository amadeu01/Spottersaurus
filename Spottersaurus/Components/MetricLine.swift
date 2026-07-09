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

#Preview {
    VStack(spacing: 12) {
        MetricLine(label: "Training Max", value: 180)
        MetricLine(label: "1RM", value: 200)
    }
    .padding()
}
