//
//  SyncIDs.swift
//  Dipstick
//

import Foundation
import SwiftData

/// Gives every record its own `syncID`. New records get one when they're
/// first synced or backed up; at launch, any record still without one
/// (made before sync existed) gets one.
enum SyncIDs {
    static func new() -> String { UUID().uuidString }

    /// Fills in missing IDs. Returns how many were assigned.
    @discardableResult
    static func assign(in context: ModelContext) -> Int {
        var count = 0
        func fill<T: PersistentModel>(_ type: T.Type, _ keyPath: ReferenceWritableKeyPath<T, String?>) {
            for model in (try? context.fetch(FetchDescriptor<T>())) ?? [] where model[keyPath: keyPath] == nil {
                model[keyPath: keyPath] = new()
                count += 1
            }
        }
        fill(Vehicle.self, \.syncID)
        fill(FuelEntry.self, \.syncID)
        fill(MaintenanceEntry.self, \.syncID)
        fill(PartUsed.self, \.syncID)
        fill(Trip.self, \.syncID)
        fill(ScheduleItem.self, \.syncID)
        fill(TestEntry.self, \.syncID)
        fill(TestReading.self, \.syncID)
        fill(ReferencePage.self, \.syncID)
        fill(ReferencePhoto.self, \.syncID)
        if count > 0 { context.saveNow() }
        return count
    }
}
