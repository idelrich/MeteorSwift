//
//  MongoObject.swift
//  MeteorSwift
//
//  Created by Stephen Orr on 2023-07-09.
//  Copyright © 2023 Stephen Orr. All rights reserved.
//

import Foundation

public protocol MongoObject : Identifiable, Hashable, Equatable {
    var _id: String { get set }
}

public extension MongoObject {
    var id : String { _id }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(_id)
    }
}

