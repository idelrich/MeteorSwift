//
//  Collection.swift
//  LiveScores
//
//  Created by Stephen Orr on 2018-07-01.
//  Copyright © 2018 Stephen Orr. All rights reserved.
//

import Foundation

/// A closure that takes the expected type and returns Bool if the record should be included.
public typealias MeteorMatcher<T>       = (T) -> Bool
/// A closure that takes the expected type and returns the descired sort order.
public typealias MeteorSorter<T>       = (T, T) -> Bool
/// A closure that nortifies a client when changes to a collection occur.
public typealias CollectionCallback<T> = (ChangedReason, String, T?) -> Void

/// When watching changes in a Meteor collection, this enumeratiuon
/// describes what kind of change was reported by Meteor
///
/// - added: Simple record add, record was appended to the end of the collection
/// - addedBefore: Record was to the collection before the specified index
/// - movedBefore: Collection sort order was changed, causing this record to move
/// - removed: This record was deleted
/// - changed: This record was updated with new contents.
public enum ChangedReason: String {
    case added
    case addedBefore
    case movedBefore
    case removed
    case changed
}

public protocol MongoObject {
    var _id: String { get set }
}

/// MongoCollection
///
/// Provides similar functionality to Mongo objects in native Meteor including
/// the ability to register "watchers" that are notified as well a perform find
/// and findOne like operations including sorting.
public struct MongoCollection<T> {
    private let watcher     : MeteorWatcher<T>
    
    let meteor              : MeteorClient
    let name                : String

    /// Create a MongoCollection on the client
    ///
    /// - Parameters:
    ///   - meteor: Instance of meteor this collection can be found in
    ///   - collection: Name of the collection
    public init(meteor: MeteorClient, collection: String) {
        self.meteor = meteor
        self.name = collection
        watcher = MeteorWatcher(meteor: meteor, collection: collection)
        
        if let coder = T.self as? CollectionDecoder.Type {
            meteor.registerCodable(collection, collectionCoder: coder)
        }
    }

    /// Insert an object into this collection
    ///
    /// - Parameters:
    ///   - object: Object to insert
    ///   - responseCallback: (Optional) callback to be called once server completes this response
    /// - Returns: _id iof newly inserted object (or nil)
    public func insert(_ object: T, responseCallback: MeteorClientMethodCallback? = nil) -> String? {
        return meteor.insert(into: name, object: object, responseCallback: responseCallback)
    }
    /// Inserts a value (typically taken from local store) into the
    /// collection without waiting for it to come from the server or sending it
    /// to the server.
    ///
    /// - Parameters:
    ///     item:
    @discardableResult
    public func add(item: T) -> Bool {
        if let _id = mongoId(for: item) {
            meteor.add(item: item, forId: _id, into: name)
            return true
        }
        return false
    }
    /// Update an object in the collection
    ///
    /// - Parameters:
    ///   - _id: id if the object being updated
    ///   - changes: EJSONObj containing the required updates. Fields marked with NSNull are
    ///              $unset, while other fields are $set.
    ///   - responseCallback: (Optional) callback to be called once server completes this response
    public func update(_ _id: String, changes: EJSONObject, responseCallback: MeteorClientMethodCallback? = nil) {
        meteor.update(into: name, objectWithId: _id, changes: changes, responseCallback: responseCallback)
    }
    /// Remove an object with the specified id from this collection
    ///
    /// - Parameters:
    ///   - _id: id of object to remove from theis collection
    ///   - responseCallback: (Optional) callback to be called once server completes this response
    public func remove(_ _id: String, responseCallback: MeteorClientMethodCallback? = nil) {
        meteor.remove(from: name, objectWithId: _id, responseCallback: responseCallback)
    }
    /// Find all records that pass the provided "matching" closure, sorted by
    /// the provided (optional) sorting closure
    ///
    /// - Parameters:
    ///   - matching: (Optional) A MeteorPredicate closure that determines which records to include
    ///   - sorted: (Optional) A MeteorSorter closure that determines how to sort records.
    /// - Returns: An array of the type held in this collection
    public func find(matching: MeteorMatcher<T>? = nil, sorted: MeteorSorter<T>? = nil) -> [T] {
        
        if let collection = meteor.collections[name] {
            var results:[T] = collection.values.compactMap({
                if let item = $0 as? T, matching?(item) ?? true {
                    return item
                }
                return nil
            })
            if let sorter = sorted {
                results = results.sorted(by: sorter)
            }
            return results
        }
        return []
    }
    /// Find the first matching record for this collection after (optionally) sorting
    ///
    /// - Parameters:
    ///   - matching: A MeteorPredicate closure that determines which records to include
    ///   - sorted: (Optional) A MeteorSorter closure that determines how to sort records.
    /// - Returns: The first element of the resulting find if any
    public func findOne(matching: MeteorMatcher<T>? = nil, sorted: MeteorSorter<T>? = nil) -> T? {
        return find(matching: matching, sorted: sorted).first
    }
    /// Find the record in this collection with a Mongo _id matching the passed in
    /// value.
    ///
    /// - Parameters:
    ///   - _ _id: The Mongo _id string of the object to match (if present).
    /// - Returns: The item in the collection with matching id (if any)
    public func findOne(_ _id: String) -> T? {
        if let collection = meteor.collections[name] {
            return collection[_id] as? T
        }
        return nil
    }
    ///
    /// Returns the mongoId for an object. If the object conforms to MongoObject then
    /// this returns the _id field, otherwise if this object is an EJSONObject, then the
    /// return value is the value for the "_id" key, otherwise nil is returned.
    ///
    /// - Parameters:
    ///      item: The object to extract the MongoId from
    private func mongoId(for item: T) -> String? {
        var _id: String?
        if let obj = item as? MongoObject {
            _id = obj._id
        } else if let obj = item as? EJSONObject {
            _id = obj["_id"] as? String
        }
        if _id == nil {
            print("MongoCollectoion: Couldn't find _id for item: \(item)")
        }
        return _id
    }
    /// Establishes a "watch" on changes to this collection.
    ///
    /// - Parameters:
    ///   - matching: A MeteorPredicate closure that determines which records to watch include
    ///   - callback: A callback that provides information about any changes to records in the collection
    /// - Returns: A String id that must be used to stop watching this collection (see stopWatching)
    public func watch(matching: MeteorMatcher<T>? = nil, callback: @escaping CollectionCallback<T>) -> String {
        return watcher.watch(matching: matching, callback: callback)
    }
    /// Establishes a "watch" on changes to an object in this collection with a specific _id.
    ///
    /// - Parameters:
    ///   - _ _id: A String with the Meteor objectId (_id) to establish a watch for.
    ///   - callback: A callback that provides information about any changes to records in the collection
    /// - Returns: A String id that must be used to stop watching this collection (see stopWatching)
    public func watch(_ _id: String, callback: @escaping CollectionCallback<T>) -> String {
        return watcher.watch(id: _id, callback: callback)
    }
    /// Stops a previously established "watch" on changes to this collection
    ///
    /// - Parameter watchId: An id previously returned by "watch()"
    public func stopWatching(_ watchId: String) {
        watcher.remove(watchId)
    }
    /// Removes any previously created change watcher for this collection
    public func stopAllWatches() {
        watcher.removeAll()
    }

}

class MeteorWatcher<T>: NSObject {
    private var watchList   = [String: (MeteorMatcher<T>?, CollectionCallback<T>)]()
    private var idWatchList = [String: (String, CollectionCallback<T>)]()

    private let meteor      : MeteorClient
    private let collection  : String

    init(meteor client: MeteorClient, collection name: String) {
        meteor = client
        collection = name
        
        super.init()
    }
    func watch(matching: MeteorMatcher<T>? = nil, callback: @escaping CollectionCallback<T>) -> String {
        if watchList.isEmpty {
            addObservers()
        }
        let watchId = DDPIdGenerator.nextId
        watchList[watchId] = (matching, callback)
        return watchId
    }
    func watch(id: String, callback: @escaping CollectionCallback<T>) -> String {
        if watchList.isEmpty {
            addObservers()
        }
        let watchId = DDPIdGenerator.nextId
        idWatchList[watchId] = (id, callback)
        return watchId
    }

    func remove(_ watchId: String) {
        watchList.removeValue(forKey: watchId)
        idWatchList.removeValue(forKey: watchId)
        if watchList.isEmpty && idWatchList.isEmpty {
            removeObservers()
        }
    }
    func removeAll() {
        watchList.removeAll()
        idWatchList.removeAll()
        removeObservers()
    }
    private func addObservers() {
        //
        // Get all notifications for changes to this collection
        NotificationCenter.default.addObserver(self, selector: #selector(onChange(message:)),
                                               name: Notification.Name(collection), object: meteor)
    }
    private func removeObservers() {
        NotificationCenter.default.removeObserver(self)
    }

    @objc func onChange(message: NSNotification) {
        let reason = ChangedReason(rawValue: message.userInfo!["msg"] as! String) ?? .added
        let _id = message.userInfo!["_id"] as! String
        
        for (_, (id, callback)) in idWatchList {
            if id == _id {
                let item = message.userInfo!["result"] as? T
                callback(reason, _id, item)
                return
            }
        }
        for (_, (matching, callback)) in watchList {
            guard reason != .removed else {
                callback(reason, _id, nil)
                continue
            }
            let item = message.userInfo!["result"] as? T
            if let item = item, let matching = matching, !matching(item) { continue }
            callback(reason, _id, item)
        }
    }
}



