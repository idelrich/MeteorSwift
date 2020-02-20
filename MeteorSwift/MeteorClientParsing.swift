//
//  MeteorClientParsing.swift
//  LiveScores
//
//  Created by Stephen Orr on 2018-06-24.
//  Copyright © 2018 Stephen Orr. All rights reserved.
//

import Foundation

extension MeteorClient { // Parsing
    func handleMethodResult(withMessageId messageId: String, message: DDPMessage)                           {
        if _methodIds.contains(messageId) {
            let callback = _responseCallbacks[messageId]
            if let errorDesc = message["error"] as? EJSONObject {
                let userInfo = [NSLocalizedDescriptionKey: errorDesc["message"] as? String ?? "Missing Error Message"]
                let responseError = NSError(domain: errorDesc["errorType"] as? String ?? "Method Error",
                                            code: errorDesc["error"] as? Int ?? -1,
                                            userInfo:userInfo)
                callback?(.failure(responseError))
            } else {
                callback?(.success(message))
            }
            _responseCallbacks.removeValue(forKey:messageId)
            _methodIds.remove(messageId)
        }
    }
    func handleAdded(message: DDPMessage)                                                                   {
        if let collection = message["collection"] as? String {
            let (_id, value) = parseObjectAndAddToCollection(message)
            sendNotification(for: .added, collection: collection, id: _id, value: value)
        }
    }
    func handleAddedBefore(message: DDPMessage)                                                             {
        if let collection = message["collection"] as? String {
            let beforeId = message["before"] as! String
            let (_id, value) = parseObjectAndAddToCollection(message, beforeId: beforeId)
            sendNotification(for: .addedBefore, collection: collection, id: _id, value: value)
        }
    }
    func handleMovedBefore(message: DDPMessage)                                                             {
        
        if let collection = message["collection"] as? String {
            let (_id, value) = parseMovedBefore(message)
            sendNotification(for: .movedBefore, collection: collection, id: _id, value: value)
        }
    }
    func handleRemoved(message: DDPMessage)                                                                 {
        if let collection = message["collection"] as? String {
            let (_id, value) = parseRemoved(message)
            sendNotification(for: .removed, collection: collection, id: _id, value: value)
        }
    }
    func handleChanged(message: DDPMessage)                                                                 {
        if let collection = message["collection"] as? String {
            let (_id, value) = parseObjectAndUpdateCollection(message)
            sendNotification(for: .changed, collection: collection, id: _id, value: value)
        }
    }
    
    private func parseMovedBefore(_ message:DDPMessage) -> (String, Any)                                    {
        
        let _id = message["id"] as! String // NSCopying
        let collectionName = message["collection"] as! String

        var value = ["_id": _id] as Any
        if var collection = collections[collectionName] {
             if let beforeDocumentId = message["before"] as? String {
                
                // Move document to before index
                let currentIndex = collection.index(ofKey: _id)
                let moveToIndex = collection.index(ofKey: beforeDocumentId)
                
                if let _ = currentIndex, let moveToIndex = moveToIndex {
                    
                    //remove object from its current place
                    value = collection.value(forKey: _id) as Any
                    collection.remove(key: _id)
                    
                    //insert object at before index
                    collection.insert(value, for: _id, at:moveToIndex)
                }
                
            } else {
                // Document doesn't exist, add it to end
                collection.add(value, for: _id)
            }
            collections[collectionName] = collection
            value = collection[_id]!
        }
        return (_id, value)
    }
    private func parseObjectAndAddToCollection(_ message: DDPMessage) -> (String, Any)                      {
        
        let collectionName = message["collection"] as! String
        var collection = collections[collectionName, default: MeteorCollection()]
        //
        // Create the basic JSON Object by copying the fields.
        let (_id, value) = mongoObject(with: message)
        if let collectionCoder = codables[collectionName] {
            //
            // This collection is codable, convert it.
            do {
                let data = try JSONSerialization.data(withJSONObject: value, options: [])
                
                if let result = try collectionCoder.decode(data: data, decoder: jsonDecoder) {
                    collection.add(result, for: _id)
                    collections[collectionName] = collection
                    return (_id, result)
                }
            } catch {
                print("MeteorSwift: Failed to decode element in \(collectionName) - reported error \(error.localizedDescription)")
                print("MeteorSwift: Raw Data \(value)")
            }
        } else {
            //print("MeteorSwift: No decoder for collection \(collectionName)")
        }
        collection[_id] = value
        collections[collectionName] = collection
        return (_id, value)
    }
    private func parseObjectAndAddToCollection(_ message: DDPMessage, beforeId: String?) -> (String, Any)   {

        let collectionName = message["collection"] as! String
        var collection = collections[collectionName, default: MeteorCollection()]
        //
        // Create the basic JSON Object by copying the fields.
        let (_id, value) = mongoObject(with: message)

        if let collectionCoder = codables[collectionName] {
            //
            // This collection is codable, convert it.
            do {
                let data = try JSONSerialization.data(withJSONObject: value, options: [])
                if let result = try collectionCoder.decode(data: data, decoder: jsonDecoder) {
                    if let documentId = beforeId {
                        if let documentIndex = collection.index(ofKey: documentId) {
                            collection.insert(value, for: _id, at: documentIndex)
                        }
                    } else {
                        collection[_id] = result
                    }
                    collections[collectionName] = collection
                    return (_id, result)
                }
            } catch {
                print("MeteorSwift: Failed to decode element in \(collectionName) - reported error \(error.localizedDescription)")
                print("MeteorSwift: Raw Data \(value)")
            }
            return (_id, value)
        } else {
            if let documentId = beforeId {
                if let documentIndex = collection.index(ofKey: documentId) {
                    collection.insert(value, for: _id, at: documentIndex)
                }
            } else {
                collection[_id] = value
            }
            collections[collectionName] = collection
            return (_id, value)
        }
    }
    private func parseObjectAndUpdateCollection(_ message: DDPMessage) -> (String, Any)                     {
        
        let _id = message["id"] as! String // NSCopying
        let collectionName = message["collection"] as! String
        
        var collection = collections[collectionName, default: MeteorCollection()]
        
        //
        // Get the EJSONObject version of the current data.
        if let object = collection[_id],
            var json = ddp!.convertToEJSON(object: object) {
            //
            // <json> is now the current version of the onject.
            //
            // Apply the updates
            if let changes = message["fields"] as? EJSONObject {
                for (key, value) in changes {
                    json[key] = value
                }
            }
            if let cleared = message["cleared"] as? [String] {
                for key in cleared {
                    json.removeValue(forKey:key)
                }
            }
            //
            // And now decode it back to the original object type (if possible)
            if let collectionCoder = codables[collectionName] {
                do {
                    if let data = try? JSONSerialization.data(withJSONObject: json, options: []) {
                        if let result = try collectionCoder.decode(data: data, decoder: jsonDecoder) {
                            collection[_id] = result
                            collections[collectionName] = collection
                        }
                    }
                } catch {
                    print("MeteorSwift: Failed to update element in \(collectionName) - reported error \(error.localizedDescription)")
                    print("MeteorSwift: Raw Data \(json)")
                }
            } else {
                collection[_id] = json
                collections[collectionName] = collection
            }
            return (_id, collection[_id]!)
        } else {
            //
            // Object is not in the collection currently, shouldn't happen?
            // Or couldn'r be encoded to EJSONObject, which also shouldn't happen
            print("********************")
            print("Unexpected code path - couldn't decode/encode original object for \(message)")
            print("********************")
            //
            // Decode the new object and remove any fields before saving it.
            var (_id, value) = mongoObject(with: message)
            if let cleared = message["cleared"] as? [String] {
                for key in cleared {
                    value.removeValue(forKey:key)
                }
            }
            collection[_id] = value
            
            collections[collectionName] = collection
            return (_id, value)
        }
    }
    private func parseRemoved(_ message: DDPMessage) -> (String, Any?)                                      {
        let _id     = message["id"] as! String
        var value  : Any?
        if let collectionName = message["collection"] as? String,
            var collection = collections[collectionName] {
            value = collection.value(forKey: _id)
            collection.remove(key: _id)
            collections[collectionName] = collection
        }
        return (_id, value)
    }
    
    private func mongoObject(with message: DDPMessage) -> (String, EJSONObject)                             {
        let _id = message["id"] as! String
        var result = ["_id": _id] as EJSONObject
        for (key, value) in message["fields"] as! EJSONObject {
            result[key] = value
        }
        return (_id, result)
    }
    private func sendNotification(for reason: ChangedReason, collection: String, id: String, value: Any?)   {

        var userInfo:[String: Any] = ["msg": reason.rawValue, "_id": id]
        if let value = value {
            userInfo["result"] = value
        }
        if let watcher = _collectionWatchers[collection] {
            watcher.onChange(id, reason: reason, object: value)
        }

    }
}
