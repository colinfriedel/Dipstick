//
//  ScheduleItem.swift
//  Dipstick
//

import Foundation
import SwiftData

/// One line of a car's factory maintenance schedule (from the owner's
/// manual), e.g. "Replace engine oil, every 10,000 mi or 6 months". Progress
/// is measured from the latest logged service whose type is `serviceType`.
@Model
final class ScheduleItem {
    /// Stays the same on every phone, for iCloud sync and sharing. Optional
    /// so existing records get their own (see `SyncIDs.assign`); a default
    /// would give them all the same one.
    var syncID: String?
    /// As the manual words it: "Replace engine oil".
    var name: String = ""
    /// The logged service that counts as doing this: "Oil change".
    var serviceType: String = ""
    var everyMiles: Int?
    var everyMonths: Int?
    /// A different first interval, for "at 120,000 mi or 10 years, then every
    /// 60,000 mi or 5 years". Used until the service is first logged.
    var firstMiles: Int?
    var firstMonths: Int?
    /// Your own interval, replacing the factory one field by field (e.g. oil
    /// every 5,000 mi instead of 10,000). nil uses the factory value.
    var customEveryMiles: Int?
    var customEveryMonths: Int?
    /// For items with no interval: "At each fuel stop".
    var note: String?
    /// Position in the manual's order.
    var order: Int = 0
    var vehicle: Vehicle?

    init(name: String, serviceType: String, rule: FactorySchedule.Rule = .init(),
         note: String? = nil, order: Int = 0) {
        self.name = name
        self.serviceType = serviceType
        self.note = note
        self.order = order
        self.rule = rule
    }

    var hasCustomInterval: Bool { customEveryMiles != nil || customEveryMonths != nil }

    /// The rule progress is measured with: your interval where set, else the
    /// factory one.
    var effectiveRule: FactorySchedule.Rule {
        var rule = rule
        if let customEveryMiles { rule.everyMiles = customEveryMiles }
        if let customEveryMonths { rule.everyMonths = customEveryMonths }
        return rule
    }

    /// The factory rule, as in the owner's manual.
    var rule: FactorySchedule.Rule {
        get {
            .init(everyMiles: everyMiles, everyMonths: everyMonths,
                  firstMiles: firstMiles, firstMonths: firstMonths)
        }
        set {
            everyMiles = newValue.everyMiles
            everyMonths = newValue.everyMonths
            firstMiles = newValue.firstMiles
            firstMonths = newValue.firstMonths
        }
    }
}
