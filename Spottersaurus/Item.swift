//
//  Item.swift
//  Spottersaurus
//
//  Created by Amadeu Cavalcante on 29/06/26.
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
