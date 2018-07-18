//
//  EJSON.swift
//  LiveScores
//
//  Created by Stephen Orr on 2018-06-24.
//  Copyright © 2018 Stephen Orr. All rights reserved.
//

import Foundation

public struct EJSONDate: Codable {
    enum CodingKeys : String, CodingKey { case _elapsed = "$date" }
    private let _elapsed: Int
    
    public init(date: Date) {
        _elapsed = Int(date.timeIntervalSince1970*1000)
    }
    public var date:Date { return Date(timeIntervalSince1970: ms) }
    public var ms:TimeInterval { return TimeInterval(_elapsed)/1000 }
}

public struct EJSONData: Codable {
    enum CodingKeys : String, CodingKey { case _data = "$binary" }
    private let _data: String
    
    public var data:Data {
        if let result = Data(base64Encoded: _data, options: []) {
            return result
        }
        print("MeteorSwift: Error: couldn't parse EJSON data - returning empty Data()")
        return Data()
    }
}

public extension Date { // (EJSON Date)
    public var bson:[String: Double] { return ["$date": timeIntervalSince1970*1000.0] }
}

public extension Data { // (EJSON Data)
    public var bson:[String: String] { return ["$binary": base64EncodedString(options: [])] }
}

