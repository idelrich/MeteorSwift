//
//  EJSON.swift
//  LiveScores
//
//  Created by Stephen Orr on 2018-06-24.
//  Copyright © 2018 Stephen Orr. All rights reserved.
//

import Foundation

public struct EJSONDate: Codable, CollectionDecoder, Comparable, Equatable {
    enum CodingKeys : String, CodingKey { case _elapsed = "$date" }
    private let _elapsed: Int64
    
    public init(date: Date) {
        _elapsed = Int64(date.timeIntervalSince1970*1000)
    }
    public var date:Date { return Date(timeIntervalSince1970: ms) }
    public var ms:TimeInterval { return TimeInterval(_elapsed)/1000 }

    static public func  <(lhs: EJSONDate, rhs:EJSONDate)  -> Bool { lhs._elapsed  < rhs._elapsed }
    static public func  >(lhs: EJSONDate, rhs:EJSONDate)  -> Bool { lhs._elapsed  > rhs._elapsed }
    static public func ==(lhs: EJSONDate, rhs:EJSONDate)  -> Bool { lhs._elapsed == rhs._elapsed }
    static public func <=(lhs: EJSONDate, rhs:EJSONDate)  -> Bool { lhs._elapsed <= rhs._elapsed }
    static public func >=(lhs: EJSONDate, rhs:EJSONDate)  -> Bool { lhs._elapsed >= rhs._elapsed }
}


public struct EJSONData: Codable, CollectionDecoder {
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
    var bson:[String: Double] { return ["$date": timeIntervalSince1970*1000.0] }
}

public extension DateFormatter {
    static func localizedString(from: EJSONDate, dateStyle: Style, timeStyle: Style) -> String {
        return DateFormatter.localizedString(from: from.date, dateStyle: dateStyle, timeStyle: timeStyle)
    }
}

public extension Data { // (EJSON Data)
    var bson:[String: String] { return ["$binary": base64EncodedString(options: [])] }
}
