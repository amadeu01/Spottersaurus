import Foundation
import SpottersaurusKit

enum LiveSetCalibrationState: Equatable {
    case fallback(CalibrationValues)
    case collecting(candidate: CalibrationValues?)
    case ready(CalibrationValues)

    var values: CalibrationValues {
        switch self {
        case .fallback(let values), .ready(let values):
            values
        case .collecting(let candidate):
            candidate ?? .fallback(for: .bench)
        }
    }

    var isCollecting: Bool {
        if case .collecting = self { return true }
        return false
    }
}

extension CalibrationValues {
    static func fallback(for lift: LiftKind) -> CalibrationValues {
        CalibrationValues(
            lift: lift,
            baselineConcentricSeconds: 1.0,
            velocityBandLowerMS: lift.usesVelocityPath ? 0.18 : 0,
            velocityBandUpperMS: lift.usesVelocityPath ? 0.75 : 0,
            repCount: 0
        )
    }
}
