//
//  DependencyProvider.swift
//  LiveScores
//
//  Created by Stephen Orr on 2018-06-24.
//  Copyright © 2018 Stephen Orr. All rights reserved.
//

import Foundation
import SocketRocket

struct DependencyProvider                                                   {
    static func provideSRWebSocket(withRequest: URLRequest) -> SRWebSocket  {
        return SRWebSocket(urlRequest: withRequest)
    }
}

struct DDPIdGenerator                          {
    static var methodCallCount = 0
    
    static var nextId:String                    {
        get {
            methodCallCount += 1
            return String(methodCallCount)
        }
    }
}

