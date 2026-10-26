//
//  ServiceNotesMove.swift
//  Dipstick
//

import Foundation
import SwiftData

extension Vehicle {
    /// Every logged service of a type on this car, newest first.
    func serviceEntries(ofType type: String) -> [MaintenanceEntry] {
        (maintenanceEntries ?? [])
            .filter { $0.serviceType.caseInsensitiveCompare(type) == .orderedSame }
            .sorted { ($0.date, $0.odometer) > ($1.date, $1.odometer) }
    }

    /// Earlier services of a type that have notes or photos, newest first,
    /// leaving out the one being edited.
    func pastServiceNotes(ofType type: String, excluding: MaintenanceEntry? = nil) -> [MaintenanceEntry] {
        serviceEntries(ofType: type).filter {
            $0.hasNotesOrPhotos && $0.persistentModelID != excluding?.persistentModelID
        }
    }

    /// An old "For next time" page for a service that was never logged
    /// (so it had nowhere to move to), if it has anything on it.
    func leftoverServicePage(ofType type: String) -> ReferencePage? {
        referencePage(kind: ReferencePage.serviceKind, name: type).flatMap { $0.isEmpty ? nil : $0 }
    }
}

/// Services used to keep one "For next time" page per type. Now each logged
/// service has its own notes and photos, so each old page moves onto the
/// latest service of its type: its notes go after that service's notes and
/// its photos go with them. Pages for services never logged stay and still
/// show with the past notes. Runs at launch; does nothing once moved.
enum ServiceNotesMove {
    static func run(in context: ModelContext) {
        let pages = (try? context.fetch(FetchDescriptor<ReferencePage>())) ?? []
        var moved = false
        for page in pages where page.kind == ReferencePage.serviceKind {
            guard let latest = page.vehicle?.serviceEntries(ofType: page.name).first else { continue }

            let pageNotes = page.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            if !pageNotes.isEmpty {
                let existing = (latest.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                latest.notes = existing.isEmpty ? pageNotes : existing + "\n\n" + pageNotes
            }
            var order = (latest.photos ?? []).map(\.order).max().map { $0 + 1 } ?? 0
            for photo in page.sortedPhotos {
                photo.page = nil
                photo.entry = latest
                photo.order = order
                order += 1
            }
            page.photos = []
            context.delete(page)
            moved = true
        }
        if moved { context.saveNow() }
    }
}
