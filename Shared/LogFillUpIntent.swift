//
//  LogFillUpIntent.swift
//  Dipstick (app and Control Center extension)
//

import AppIntents
import Observation

/// "Log Fill-Up": opens Dipstick at the pump scanner. Used by the Control
/// Center button, and shows up in Shortcuts, Siri and the Action button.
/// Built into both the app and the Control Center extension; it always runs
/// in the app, which it opens.
struct LogFillUpIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Fill-Up"
    static let description = IntentDescription("Opens Dipstick's pump scanner to log a fill-up.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickActions.shared.fillUpRequested = Date()
        return .result()
    }
}

/// Requests from outside the app (Control Center, Shortcuts), picked up by
/// Home.
@MainActor @Observable
final class QuickActions {
    static let shared = QuickActions()
    /// Set when a fill-up is asked for; Home handles it and clears it.
    var fillUpRequested: Date?
}
