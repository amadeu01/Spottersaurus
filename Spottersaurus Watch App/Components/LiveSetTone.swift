import SwiftUI
import SpottersaurusKit

enum LiveSetTone {
    case optimal
    case caution
    case alert

    var color: Color {
        switch self {
        case .optimal: Theme.Colors.optimal
        case .caution: Theme.Colors.caution
        case .alert: Theme.Colors.alert
        }
    }
}
