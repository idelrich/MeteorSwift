//
//  SwiftDDP.swift
//  LiveScores
//
//  Created by Stephen Orr on 2018-06-24.
//  Copyright © 2018 Stephen Orr. All rights reserved.
//

import Foundation
import SocketRocket

protocol SwiftDDPDelegate {
    func didOpen()
    func didReceive(message: DDPMessage)
    func didReceive(connectionError: Error)
    func didReceiveConnectionClose()
}

public typealias DDPMessage = [AnyHashable : Any]

class SwiftDDP: NSObject {
    
    fileprivate var urlString   : String
    fileprivate var delegate    : SwiftDDPDelegate?
    fileprivate var webSocket   : SRWebSocket?

    fileprivate let jsonEncoder = JSONEncoder()
    
    init(withURLString: String, delegate: SwiftDDPDelegate?)                                            {
        self.urlString  = withURLString
        self.delegate   = delegate
    }
    var socketNotOpen:Bool {
        return socketState != SRReadyState.OPEN
    }
    func connectWebSocket()                                                                                 {
        // connect to the underlying websocket
        disconnectWebSocket()
        setupWebSocket()
        webSocket?.open()
    }
    func disconnectWebSocket()                                                                              {
        // disconnect from the websocket
        closeConnection()
    }
    func ping(id: String?)                                                                                  {
        // ping (client -> server):
        // id: string (the id for the ping)
        var fields = ["msg": "ping"]
        if let id = id {
            fields[id] = id
        }
        let json = buildJSON(withFields:fields, parameters:nil)
        webSocket?.send(json)
    }
    func pong(id: String?)                                                                                  {
        // pong (client -> server):
        // id: string (the id send with the ping)
        var fields = ["msg": "pong"]
        if let id = id {
            fields[id] = id
        }
        let json = buildJSON(withFields:fields, parameters:nil)
        webSocket?.send(json)
    }
    func connect(withSession: String?, version: String, support: [String])                                  {
        // connect (client -> server)
        //  session: string (if trying to connectWebSocket to an existing DDP session)
        //  version: string (the proposed protocol version)
        //  support: array of strings (protocol versions supported by the client, in order of preference)

        // TODO: Why os the Session string passed in and ignored...?
        
        let fields = ["msg": "connect", "version": version, "support": support] as EJSONObject
        let json = buildJSON(withFields:fields, parameters:nil)
        webSocket?.send(json)
    }
    func subscribe(withId id: String, name: String, parameters: [Any]?)                                     {
        //sub (client -> server):
        //  id: string (an arbitrary client-determined identifier for this subscription)
        //  name: string (the name of the subscription)
        //  params: optional array of EJSON items (parameters to the subscription)
        let fields = ["msg": "sub", "name": name, "id": id]
        let json = buildJSON(withFields:fields, parameters:parameters)
        webSocket?.send(json)
    }
    func unsubscribe(withId id: String)                                                                     {
        //unsub (client -> server):
        //  id: string (an arbitrary client-determined identifier for this subscription)
        let fields = ["msg": "unsub", "id": id]
        let json = buildJSON(withFields: fields, parameters: nil)
        webSocket?.send(json)
    }
    func method(withId id: String, method: String, parameters: [Any]?)                                      {
        //method (client -> server):
        //  method: string (method name)
        //  params: optional array of EJSON items (parameters to the method)
        //  id: string (an arbitrary client-determined identifier for this method call)
        let fields = ["msg": "method", "method": method, "id": id]
        let json = buildJSON(withFields: fields, parameters: parameters)
        webSocket?.send(json)
    }

    var url:String { get { return urlString } }
    var socketState:SRReadyState { get { return webSocket?.readyState ?? SRReadyState.CLOSED } }

    func convertToEJSON(object: Any) -> EJSONObject? {
        //
        // Handle the "finicky" types (Data and Date) as well as
        // the self encoding types (conforming to CollectionDecoder)
        // and pass through the rest.

        //
        // TODO: Add support for nested arrays...
        do {
            if let date = object as? Date {
                return date.bson
            } else if let data = object as? Data {
                return data.bson
            } else if let encodable = object as? CollectionDecoder {
                if let data = try encodable.encode(encoder: jsonEncoder) {
                    let encoded = try JSONSerialization.jsonObject(with: data, options: [])
                    if let result = encoded as? EJSONObject {
                        return result
                    
                    } else {
                        print("MeteorSwift: Encoded \(object) is not EJSONObject")
                    }
                }
            }
        } catch {
            print("MeteorSwift: Failed to encode \(object) - reported error \(error.localizedDescription)")
        }
        if let result = object as? EJSONObject {
            return result
        }
        return nil
    }
}

extension SwiftDDP { // MARK - Internal
    func buildJSON(withFields: EJSONObject, parameters: [Any]?) -> String                            {
        
        var params = withFields
        if let parameters = parameters {
            //
            // Go through the parameters and try to encode any that we can.            
            params["params"] = parameters.map {
                if let array = $0 as? [Any] {
                    let encoded = array.compactMap { convertToEJSON(object: $0) }
                    if encoded.count == array.count {
                        return encoded
                    } else {
                        return array
                    }
                }
                return convertToEJSON(object: $0) ?? $0
            } as [Any]
        }
        if let data = try? JSONSerialization.data(withJSONObject: params, options: [])    {
            return String(data: data, encoding: .utf8) ?? ""
        }
        return ""
    }
    func setupWebSocket()                                                                           {
        if let url = URL(string: urlString) {
            let request = URLRequest(url: url)
            webSocket = DependencyProvider.provideSRWebSocket(withRequest:request)
            webSocket?.delegate = self
        }
    }
    func closeConnection()                                                                          {
        webSocket?.close()
        webSocket?.delegate = nil
        webSocket = nil
    }
}

extension SwiftDDP: SRWebSocketDelegate {
    public func webSocketDidOpen(_ webSocket: SRWebSocket!)                                                        {
        delegate?.didOpen()
    }
    public func webSocket(_ webSocket: SRWebSocket!, didFailWithError error: Error!)                               {
        delegate?.didReceive(connectionError: error)
    }
    public func webSocket(_ webSocket: SRWebSocket!, didCloseWithCode code: Int, reason: String!, wasClean: Bool)  {
        delegate?.didReceiveConnectionClose()
    }
    public func webSocket(_ webSocket: SRWebSocket!, didReceiveMessage message: Any!)                              {
        if let message = message as? String {
            if let data = message.data(using: .utf8) {
                if let message = try? JSONSerialization.jsonObject(with: data, options: []) {
                    if let message = message as? DDPMessage {
                        delegate?.didReceive(message: message)
                    }
                }
            }
        }
    }
}
