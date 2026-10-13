//
//  DueStatusStyle.swift
//  Dipstick
//

import SwiftUI

/// How each due status looks wherever it's shown.
extension MaintenanceDueCalculator.Status {
    var color: Color {
        switch self {
        case .ok: .secondary
        case .dueSoon: .orange
        case .overdue: .red
        }
    }

    var systemImage: String {
        switch self {
        case .ok: "checkmark.circle"
        case .dueSoon: "clock.badge.exclamationmark"
        case .overdue: "exclamationmark.triangle.fill"
        }
    }
}
