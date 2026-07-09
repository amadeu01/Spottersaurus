import SwiftUI
import SpottersaurusKit

struct RepMetricRowView: View {
    var rep: RepMetric

    var body: some View {
        HStack {
            Text("#\(rep.repIndex + 1)")
                .font(.system(.caption, design: .rounded, weight: .bold))
                .frame(width: 32, alignment: .leading)
            Text("\(rep.meanVelocityMS.formatted(.number.precision(.fractionLength(2)))) m/s")
            Spacer()
            Text("\(rep.concentricSeconds.formatted(.number.precision(.fractionLength(2)))) s")
            if rep.flaggedStall {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.Colors.caution)
            }
        }
        .font(.system(.caption, design: .rounded, weight: .semibold))
        .monospacedDigit()
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 8) {
        RepMetricRowView(rep: RepMetric(repIndex: 0, concentricSeconds: 1.1, peakVelocityMS: 0.6, meanVelocityMS: 0.45))
        RepMetricRowView(rep: RepMetric(repIndex: 1, concentricSeconds: 1.4, peakVelocityMS: 0.48, meanVelocityMS: 0.36))
        RepMetricRowView(rep: RepMetric(repIndex: 2, concentricSeconds: 2.3, peakVelocityMS: 0.22, meanVelocityMS: 0.15, flaggedStall: true))
    }
    .padding()
}
