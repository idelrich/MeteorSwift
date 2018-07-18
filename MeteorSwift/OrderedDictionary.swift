//
//  OrderedDictionary.swift
//  LiveScores
//
//  Created by Stephen Orr on 2018-06-26.
//  Copyright © 2018 Stephen Orr. All rights reserved.
//

import Foundation

struct OrderedDictionary<K:Hashable, V: Any> {

    fileprivate var _keys   = [K]()
    fileprivate var _values = [V]()
    fileprivate var _pairs  = [K : V]()

    // mark - Initialization
    public init() {}
    public init(withOrderedDictionary: OrderedDictionary<K, V>) {
        let keys = withOrderedDictionary.keys
        let values = withOrderedDictionary.values
        self.init(with: values, for: keys)
    }
    public init(withContentsOfDictionary entries: [K: V]) {

        var keys = [K]()
        var values = [V]()
        for (key, value) in entries {
            keys.append(key)
            values.append(value)
        }
        self.init(with: values, for: keys)
    }
    public init(with values: [V], for keys: [K]) {
        
        guard values.count == keys.count else {
            print("OrderedDictionary: The number of values does not match the number of keys")
            return
        }
        guard Set<K>(keys).count == keys.count else {
            print("OrderedDictionary: There are duplicate keys on initialization")
            return
        }
        _keys = keys
        _values = values
        _pairs = Dictionary(uniqueKeysWithValues: zip(keys, values))
    }
    // Mark - Querying
    public func contains(key: K) -> Bool {
        return _keys.contains(key)
    }
    public var count: Int { get { return _keys.count } }
    public var lastValue: V? { get { return _values.last } }
    public var lastKey: K? { get { return _keys.last } }
    public var last: [K:V]? {
        get {
            guard count>0 else { return nil }
            return [lastKey!: lastValue!]
        }
    }
    public var firstValue: V? { get { return _values.first } }
    public var firstKey: K? { get { return _keys.first } }
    public var first: [K:V]? {
        get {
            guard count>0 else { return nil }
            return [firstKey!: firstValue!]
        }
    }
    public func value(at index: Int) -> V {
        return _values[index]
    }
    public func key(at index: Int) -> K {
        return _keys[index]
    }
    public func entry(at index: Int) -> [K:V] {
        return [key(at: index) : value(at: index)]
    }
    public func values(atIndices: IndexSet) -> [V] {
        var result = [V]()
        for index in atIndices {
            result.append(value(at: index))
        }
        return result
    }
    public func keys(atIndices: IndexSet) -> [K] {
        var result = [K]()
        for index in atIndices {
            result.append(key(at: index))
        }
        return result
    }
    public func entries(atIndices: IndexSet) -> OrderedDictionary {
        var keys = [K]()
        var values = [V]()
        for index in atIndices {
            keys.append(key(at: index))
            values.append(value(at: index))
        }
        return OrderedDictionary(with: values, for: keys)
    }
    public func unorderedEntries(atIndices: IndexSet) -> [K: V] {
        var result = [K: V]()
        for index in atIndices {
            result[key(at: index)] = value(at: index)
        }
        return result
    }
    public var unorderedDictionary:[K: V] {
        get {
            return Dictionary(uniqueKeysWithValues: zip(keys, values))
        }
    }
    public var keys:[K] { get { return _keys } }
    public var values:[V] { get { return _values } }

    public func value(forKey: K) -> V? {
        return _pairs[forKey]
    }
    public subscript(key: K) -> V? {
        get {
            return _pairs[key]
        }
        mutating set {
            guard let value = newValue else {
                remove(key: key)
                return
            }
            if let i = index(ofKey: key) {
                _pairs[key] = newValue
                _values.remove(at: i)
                _values.insert(value, at: i)
            } else {
                self.add(value, for: key)
            }
            
        }
    }
    public func values(forKeys: [K], notFoundMarker: V) -> [V] {
        var results = [V]()
        for key in keys {
            results.append(_pairs[key] ?? notFoundMarker)
        }
        return results
    }
    // MARK - Enumeration
    public var valueEnumerator: EnumeratedSequence<[V]> { get { return values.enumerated() } }
    public var keyEnumerator: EnumeratedSequence<[K]> { get { return keys.enumerated() } }
    public var entryEnumerator: EnumeratedSequence<[K:V]> { get { return _pairs.enumerated() } }

    // MARK - Searching

    public func index(ofKey key: K) -> Int? {
        return keys.index(of: key)
    }
    //func index(of value: V) -> Int? {
    //    return values.index(of: value)
    //}
    public func index(of entry: [K: V]) -> Int? {
        for (key, _) in entry {
            return index(ofKey: key)
        }
        return nil // Only reaches here is <entry> is empty
    }

    // Mark - Description
    public var description: String {
        get {
            var string = "{"
            for (index, key) in keys.enumerated() {
                let value = values[index]
                string += "\(key) = \(value)"
                if (index < self.count - 1) {
                    string += ";"
                }
            }
            return string
        }
    }

    // mark - NSCoding
    public func encode(with coder: NSCoder) {
        coder.encode(values, forKey:"SwODValues")
        coder.encode(keys, forKey:"SwODKeys")
    }
    public init?(with decoder: NSCoder) {
        guard let keys = decoder.decodeObject(forKey: "SwODKeys") as? [K],
            let values = decoder.decodeObject(forKey: "SwODValues") as? [V] else {
                return nil
        }
        self.init(with: values, for: keys)
    }

    // Mutating Support
    public mutating func add(_ value: V, for key: K) {
        remove(key: key)
        _pairs[key] = value
        _keys.append(key)
        _values.append(value)
    }
    public mutating func add(_ entry: [K: V]) {
        for (key, value) in entry {
            add(value, for: key)
        }
    }
    public mutating func add(_ entries: OrderedDictionary) {
        for (key, value) in zip(entries.keys, entries.values) {
            add(value, for: key)
        }
    }
    public mutating func insert(_ value: V, for key: K, at index: Int) {
        remove(key: key)
        _pairs[key] = value
        _keys.insert(key, at: index)
        _values.insert(value, at: index)
    }
    public mutating func insert(_ entries: [K: V], at index: Int) {
        for (key, value) in entries.reversed() {
            insert(value, for: key, at: index)
        }
    }
    public mutating func insert(_ entries: OrderedDictionary<K, V>, at index: Int) {
        for i in 0..<entries.count {
            insert(entries.value(at: i), for: entries.key(at: i), at: index+i)
        }
    }
    public mutating func set(_ value: V, for key: K) {
        if let i = index(ofKey: key) {
            _pairs[key] = value
            _values.remove(at: i)
            _values.insert(value, at: i)
        } else {
            self.add(value, for: key)
        }
    }
    public mutating func set(_ entries: [K: V]) {
        for (key, value) in entries {
            set(value, for: key)
        }
    }
    public mutating func set(_ entries: OrderedDictionary<K, V> ) {
        for key in entries.keys {
            set(entries[key]!, for: key)
        }
    }
    public mutating func set(_ value: V, for key: K, at index: Int) {
        if let i = self.index(ofKey: key) {
            _pairs[key] = value
            _values.remove(at: i)
            _values.insert(value, at: i)
        } else {
            insert(value, for: key, at:index)
        }
    }
    public mutating func set(_ entries: [K: V], from index: Int) {
        var i = 0
        for (key, value) in entries {
            set(value, for: key, at: index+i)
            i += 1
        }
    }
    public mutating func set(_ entries: OrderedDictionary<K, V>, from index: Int) {
        var i = 0
        for (key, value) in zip(entries.keys, entries.values) {
            set(value, for: key, at: index+i)
            i += 1
        }
    }
    // Mark - Removing

    public mutating func removeAll() {
        _keys.removeAll()
        _values.removeAll()
        _pairs.removeAll()
    }
    public mutating func removeLast() {
        guard keys.count > 0 else { return }
        remove(at: keys.count - 1)
    }
    public mutating func removeFirst() {
        guard keys.count > 0 else { return }
        remove(at: 0)
    }
    
    public mutating func remove(key: K) {
        guard let index = keys.index(of: key) else { return }
        remove(at: index)
    }
    public mutating func remove(at index: Int) {
        let key = keys[index]
        _keys.remove(at: index)
        _values.remove(at: index)
        _pairs.removeValue(forKey: key)
    }
    public mutating func remove(_ indices: IndexSet) {
        let tempKeys = keys(atIndices: indices)
        tempKeys.forEach { remove(key: $0) }
    }
    public mutating func remove(keys: [K]) {
        keys.forEach { remove(key: $0) }
    }

    // Mark - Replacing Values

    public mutating func replace(at index: Int, with value: V, for key: K) {
        let oldKey = keys[index]
        _pairs.removeValue(forKey: oldKey)
        _pairs[key] = value
        _keys.remove(at: index)
        _keys.insert(key, at: index)
        _values.remove(at: index)
        _values.insert(value, at: index)
    }
    public mutating func replace(at index: Int, with entries: [K: V]) {
        var i = 0
        for (key, value) in entries {
            replace(at: index+i, with: value, for: key)
            i += 1
        }
    }
    public mutating func replace(at indices: IndexSet, with values: [V], for keys: [K]) {

        guard indices.count == values.count else { return }
        guard indices.count == keys.count else { return }

        for (i, index) in indices.enumerated() {
            replace(at: index, with: values[i], for: keys[i])
        }
    }
    public mutating func replace(at indices: IndexSet, with entries: OrderedDictionary<K,V>) {
        guard indices.count == entries.count else { return }
        for (i, index) in indices.enumerated() {
            replace(at: index, with: entries.value(at: i), for: entries.key(at: i))
        }
    }
    public mutating func set(_ values: [V], for keys: [K]) {
        guard values.count == keys.count else { return }
        for (key, value) in zip(keys, values) {
            set(value, for: key)
        }
    }
}

//
// These Should be public IF the struct is public.
extension OrderedDictionary where V: Equatable {
    func contains(_ value: V) -> Bool {
        return values.contains(value)
    }
    func contains(_ entry: [K:V]) -> Bool {
        for (key, value) in entry {
            return contains(value, for: key)
        }
        return false    // Only gets here is entry is empty.
    }
    func allKeys(forValue: V) -> [K] {
        var result = [K]()
        for (key, value) in _pairs where value == forValue {
            result.append(key)
        }
        return result
    }
    func contains(_ value: V, for key: K) -> Bool {
        return values.contains(value) && keys.contains(key)
    }
    func index(of value: V) -> Int? {
        return values.index(of: value)
    }
    func index(of value: V, with key: K) -> Int? {
        guard _pairs[key] == value else { return nil }
        return index(ofKey: key)
    }
    func index(of entry: [K: V]) -> Int? {
        for (key, value) in entry {
            return index(of: value, with: key)
        }
        return nil // Only reaches here is <entry> is empty
    }
    
    // Mark - Removing with equating

    mutating func remove(_ entries: [K: V]) {
        for (key, value) in entries {
            remove(value, for: key)
        }
    }
    mutating func remove(_ value: V, for key: K) {
        guard let index = self.index(ofKey: key) else { return }
        guard values[index] == value else { return }
        remove(at: index)
    }
    // Mark - Comparing
    
    func firstValueInCommon(withOrderedDictionary other: OrderedDictionary) -> V? {
        return values.first(where: { other.contains($0) })
    }
    func firstKeyInCommon(withOrderedDictionary other: OrderedDictionary) -> K? {
        return keys.first(where: { other.contains(key: $0) })
    }
    func firstEntryInCommon(withOrderedDictionary other: OrderedDictionary) -> [K: V]? {
        guard let key = keys.first(where: {
            guard other.contains(key: $0) else { return false }
            return other[$0] == self[$0]
        }) else { return nil }
        
        return [key: _pairs[key]!]
    }
    func isEqual(to other: OrderedDictionary) -> Bool {
        guard self.count == other.count else { return false }
        
        return keys == other.keys && values == other.values
    }
    
    mutating func remove(_ value: V) {
        guard let index = values.index(of: value) else { return }
        remove(at: index)
    }
    mutating func remove(_ values: [V]) {
        for value in values {
            remove(value)
        }
    }
}

extension OrderedDictionary: Sequence {
    public func makeIterator() -> OrderedIterator {
        return OrderedIterator(self)
    }

    public struct OrderedIterator: IteratorProtocol {
        public typealias Element = (K, V)
        var index = 0
        let ordered: OrderedDictionary
        
        public init(_ source: OrderedDictionary) {
            ordered = source
        }
        public mutating func next() -> Element? {
            guard index < ordered.count else { return nil }
            let key = ordered.key(at: index)
            let value = ordered.value(at: index)
            index += 1
            return (key, value)
        }
    }
}
