//
//  DistanceText.swift
//  Impromptu-app
//

import Foundation

enum DistanceText {
    /// "~0.2 mi" or "~300 m", in the viewer's units. Distances are already rounded up to 100 m by the server.
    static func approximate(_ meters: Int) -> String {
        let formatted = Measurement(value: Double(meters), unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0...1))))
        return "~\(formatted)"
    }
}
