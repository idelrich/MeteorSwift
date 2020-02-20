//
//  OfflineCollection.swift
//  MeteorSwift
//
//  Created by Stephen Orr on 2019-09-19.
//  Copyright © 2019 Stephen Orr. All rights reserved.
//

import Foundation

public protocol OfflineObject where Self : Codable                      {
    var _lastUpdated_       : EJSONDate?                                { get set }
    var _wasOffline_        : Bool?                                     { get set }
    var _id                 : String                                    { get set }
}

public extension MongoCollection where T : OfflineObject                {
    func setPersistWatcher()                                            {
        //
        // Restore the cached data for this collection.
        self.restore()
        print("\(self.name) has \(self.count) objects.")
        //
        // Watch for changes coming from the server.
        var timer : Timer? = nil
        watch { (_,_,_) in
            //
            // If there is a currently active timer, invalidate it, then set a new timer
            // to persist the collection in 5 seconds.
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { (_) in
                timer = nil
                DispatchQueue.init(label: "Persisting").async {
                    try? self.persist()
                }
            }
        }
    }
    public func persist(_ fileManager: FileManager = .default) throws   {

        guard let collection = meteor.collections[name]         else { return }

        let folderURLs = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        let fileURL = folderURLs[0].appendingPathComponent(name + ".cache")
        let now = EJSONDate(date: Date())
        let encoder = JSONEncoder()
        //
        // Mark the current time (which is when the object was last valid from the server),
        // encode all objects and write them to storage.
        try encoder.encode(collection.compactMap({ (_, object) -> T? in
            guard var entry = object as? T else { return nil }
            //
            // Mark the time we cached the object.
            if entry._lastUpdated_ == nil {
                entry._lastUpdated_ = now
            }
            return entry
            
        })).write(to: fileURL)
        print("Persisted collection \(name) with \(collection.count) objects.")
    }
    public func restore(_ fileManager: FileManager = .default)          {
        //
        // Read the data from storage (if present) and
        let folderURLs = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        let fileURL = folderURLs[0].appendingPathComponent(self.name + ".cache")

        guard let data = try? Data(contentsOf: fileURL)                         else { return }
        guard let entries = try? JSONDecoder().decode([T].self, from: data)     else { return }
        //
        // Mark each entry as "_wasOffline_" so we know it came from the cache,
        // and add it directly to the collection.
        if meteor.collections[name] == nil {
            meteor.collections[name] = MeteorCollection()
        }
        entries.forEach {
            var entry = $0
            entry._wasOffline_ = true
            meteor.collections[name]?.add([entry._id: entry])
        }
    }
    public func clearOffline(_ fileManager: FileManager = .default)     {
        guard let collection = meteor.collections[name]                         else { return }
        //
        // For each entry that "_wasOffline_" remove it from the collection.
        collection.forEach({
            guard let entry = $0 as? T                                          else { return }
            guard entry._wasOffline_ == true                                    else { return }
            
            meteor.collections[name]?.remove(key: entry._id)
        })
        //
        // And delete the cache file.
        let folderURLs = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        let fileURL = folderURLs[0].appendingPathComponent(self.name + ".cache")
        try? fileManager.removeItem(at: fileURL)
    }
}
