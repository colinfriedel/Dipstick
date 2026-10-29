//
//  CarDirectoryUpdate.swift
//  Dipstick
//

import Foundation
import SwiftData
import WidgetKit

extension Vehicle {
    /// A stable ID for the car outside the app: its database ID as text,
    /// with the fields in a fixed order so it's the same every time.
    var directoryID: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(persistentModelID)).map { $0.base64EncodedString() } ?? name
    }
}

extension CarDirectory {
    /// Shares the cars with the Control Center and Lock Screen extension, and
    /// refreshes the buttons and widgets when a name or last MPG changes.
    @MainActor
    static func update(from vehicles: [Vehicle]) {
        let changed = save(vehicles.map { Car(id: $0.directoryID, name: $0.name, lastMPG: $0.mpgSummary.latest) })
        guard changed else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: "com.colinfriedel.Dipstick.FillUpWidget")
        if #available(iOS 18.0, *) {
            ControlCenter.shared.reloadControls(ofKind: "com.colinfriedel.Dipstick.LogFillUpForCar")
        }
    }
}

extension CarDirectory {
    /// The car ID in a fill-up link (dipstick://fillup?car=ID), or nil to ask.
    /// nil when the link isn't a fill-up link.
    static func carID(inFillUpURL url: URL) -> String?? {
        guard url.scheme == "dipstick", url.host == "fillup" else { return nil }
        let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "car" }?.value
        return .some(id)
    }
}
