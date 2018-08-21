//
//  MeteorDDPDelegate.swift
//  MeteorSwift
//
//  Created by Stephen Orr on 2018-07-18.
//  Copyright © 2018 Stephen Orr. All rights reserved.
//

import Foundation

extension MeteorClient : SwiftDDPDelegate {
    
    func didReceive(message: DDPMessage) {
        guard let msg = message["msg"] as? String else { return }
        
        let messageId = message["id"] as? String
        
        switch msg {
        case "result":
            if let messageId = messageId {
                handleMethodResult(withMessageId: messageId, message:message)
            } else {
                print("MeteorSwift: Missing message ID \(message)")
            }
        case "added":
            handleAdded(message: message)
        case "addedBefore":
            handleAddedBefore(message:message)
        case "movedBefore":
            handleMovedBefore(message:message)
        case "removed":
            handleRemoved(message: message)
        case "changed":
            handleChanged(message: message)
        case "ping":
            ddp?.pong(id: messageId)
        case "connected":
            connected = true
            if let sessionToken = sessionToken { //TODO check expiry date
                logon(with: sessionToken, responseCallback: nil)
            }
            delegate?.meteorClientReady()
            NotificationCenter.default.post(name: Notification.MeteorClientConnectionReady, object:self)
            makeMeteorDataSubscriptions()
        case "ready":
            if let subs = message["subs"] as? [String] {
                for readySubscriptionId in subs {
                    if let name = subscriptions[readySubscriptionId] {
                        let notificationName = Notification.Name(rawValue: "\(name)_ready")
                        NotificationCenter.default.post(name: notificationName, object:self, userInfo: ["SubscriptionId": readySubscriptionId])
                        if let callback = _subscriptionCallback[readySubscriptionId] {
                            callback(notificationName, readySubscriptionId)
                        }
                        break
                    }
                }
            }
        case "updated":
            if let methods = message["methods"] as? [String] {
                for updateMethod in methods {
                    for methodId in _methodIds {
                        if (methodId == updateMethod) {
                            let notificationName = Notification.Name(rawValue: "\(methodId)_update")
                            NotificationCenter.default.post(name: notificationName, object:self)
                            break
                        }
                    }
                }
            }
            
        case "nosub", "error":
            break
        default:
            break
        }
    }
    func didOpen() {
        websocketReady = true
        resetBackoff()
        resetCollections()
        ddp?.connect(withSession: nil, version: ddpVersion, support: _supportedVersions)
        delegate?.meteorDidConnect()
        NotificationCenter.default.post(name: Notification.MeteorClientDidConnect, object: self)
    }
    func didReceive(connectionError: Error) {
        handleConnectionError()
    }
    func didReceiveConnectionClose() {
        handleConnectionError()
    }
    
    func ping() {
        guard connected else {
            return
        }
        ddp?.ping(id: DDPIdGenerator.nextId)
    }

}

