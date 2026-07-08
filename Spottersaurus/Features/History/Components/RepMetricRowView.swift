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
