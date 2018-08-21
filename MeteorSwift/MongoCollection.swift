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

/// MongoCollection
///
/// Provides similar functionality to Mongo objects in native Meteor including
/// the ability to register "watchers" that are notified as well a perform find
/// and findOne like operations including sorting.
public struct MongoCollection<T> {
    private let meteor      : MeteorClient
    private let name        : String
    private let watcher     : MeteorWatcher<T>
    
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
    /// Establishes a "watch" on changes to this collection.
    ///
    /// - Parameters:
    ///   - matching: A MeteorPredicate closure that determines which records to watch include
    ///   - callback: A callback that provides information about any changes to records in the collection
    /// - Returns: A String id that must be used to stop watching this collection (see stopWatching)
    public func watch(matching: MeteorMatcher<T>? = nil, callback: @escaping CollectionCallback<T>) -> String {
        return watcher.watch(matching: matching, callback: callback)
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
    func remove(_ watchId: String) {
        watchList.removeValue(forKey: watchId)
        if watchList.isEmpty {
            removeObservers()
        }
    }
    func removeAll() {
        watchList.removeAll()
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



