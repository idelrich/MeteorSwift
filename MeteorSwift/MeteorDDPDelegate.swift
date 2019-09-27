//
//  MeteorDDPDelegate.swift
//  MeteorSwift
//
//  Created by Stephen Orr on 2018-07-18.
//  Copyright © 2018 Stephen Orr. All rights reserved.
//

import Foundation

extension MeteorClient : SwiftDDPDelegate {
    
    func didReceive(message: DDPMessage)                        {
        guard let msg = message["msg"] as? String else { return }
        
        let messageId = message["id"] as? String
        
        switch msg {
        case "added":               handleAdded(message: message)
        case "addedBefore":         handleAddedBefore(message:message)
        case "movedBefore":         handleMovedBefore(message:message)
        case "removed":             handleRemoved(message: message)
        case "changed":             handleChanged(message: message)
        case "ping":                ddp?.pong(id: messageId)
        
        case "result":
            if let messageId = messageId {
                handleMethodResult(withMessageId: messageId, message: message)
            } else {
                print("MeteorSwift: Missing message ID \(message)")
            }
            
        case "connected":
            connected = true
            if let sessionToken = sessionToken { //TODO check expiry date
                logon(with: sessionToken, responseCallback: nil)
            }
            connectionDelegate?.meteorClientReady()
            NotificationCenter.default.post(name: Notification.MeteorClientConnectionReady, object:self)
            makeMeteorDataSubscriptions()
        
        case "ready":
            if let subs = message["subs"] as? [String] {
                for readySubscriptionId in subs {
                    if let name = subscriptions[readySubscriptionId] {
                        _readySubscriptions[readySubscriptionId] = true
                        _subscriptionCallback[readySubscriptionId]?(name)
                    }
                }
            }
            
        case "updated":
            // TODO: Understand what this means...
            if let methods = message["methods"] as? [String] {
                for updateMethod in methods {
                    for methodId in _methodIds  where methodId == updateMethod {
                        let notificationName = Notification.Name(rawValue: "\(methodId)_update")
                        NotificationCenter.default.post(name: notificationName, object:self)
                        break
                    }
                }
            }
            
        case "nosub", "error":          break
        default:
            break
        }
    }
    func didOpen()                                              {
        websocketReady = true
        resetBackoff()
        resetCollections()
        ddp?.connect(withSession: nil, version: ddpVersion, support: _supportedVersions)
        connectionDelegate?.meteorDidConnect()
        NotificationCenter.default.post(name: Notification.MeteorClientDidConnect, object: self)
    }
    func didReceive(connectionError: Error)                     {
        handleConnectionError()
    }
    func didReceiveConnectionClose()                            {
        handleConnectionError()
    }
    func ping()                                                 {
        guard connected else {
            return
        }
        ddp?.ping(id: DDPIdGenerator.nextId)
    }
}

