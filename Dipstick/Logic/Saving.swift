//
//  Saving.swift
//  Dipstick
//

import SwiftData

extension ModelContext {
    /// Writes pending changes to disk now. SwiftData's autosave runs a little
    /// later, so a change made just before the app is closed (swiped away, or
    /// closed by iOS) could otherwise be lost.
    func saveNow() {
        guard hasChanges else { return }
        try? save()
    }
}
