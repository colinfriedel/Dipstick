//
//  Item.swift
//  Dipstick
//
//  Created by Colin Friedel on 10/12/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
