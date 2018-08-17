//
//  CollectionDecoder.swift
//  MeteorSwift
//
//  Created by Stephen Orr on 2018-08-17.
//  Copyright © 2018 Stephen Orr. All rights reserved.
//

import Foundation

/// CollectionDecoder
///
/// Allows the client to register Swift types that comply to the Codable
/// protocol and also implent the encode and decode helper methods to convert
/// EJSON objects into structures or classes. If provided the collections
/// managed by Meteor will contain concrete types rather than JSONObjects.
public protocol CollectionDecoder {
    static func decode(data: Data, decoder: JSONDecoder) throws ->  Any?
    func encode(encoder: JSONEncoder) throws -> Data?
}

public extension CollectionDecoder where Self : Codable {
    static func decode(data: Data, decoder: JSONDecoder) throws -> Any? {
        return try decoder.decode(Self.self, from: data)
    }
    func encode(encoder: JSONEncoder) throws -> Data? {
        return try encoder.encode(self)
    }
}
