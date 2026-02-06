//
//  Item.swift
//  Ag Spray Drone Field and Chemical Tracking
//
//  Created by Reggie Hetsler on 2/6/26.
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
