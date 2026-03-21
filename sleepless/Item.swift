//
//  Item.swift
//  sleepless
//
//  Created by Nguyễn Phúc Khang on 22/3/26.
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
