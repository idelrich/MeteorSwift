# MeteorSwift

MeteorSwift is a swift (and swifty) re-implementaion of [Objective-DDP](https://github.com/boundsj/ObjectiveDDP), that also takes advantage of Swift closures, codable types and some other Swift magic.

This document current to version 0.0.2

## Installation 
Install via CocoaPods:

```ruby    
pod 'MeteorSwift'
```

MeteorSwift provides a small number of key classes and a number of typealiases to make everything make sense. Here is an overview

## MeteorClient

This class provides the client side implementation for a Meteor implementation.  This includes functions to logon, signin, manage subscriptions, make function calls and CRUD Mongo Collections. Direct access to the collection is NOT supported via the MeteorClient, but is instead managed via the [MongoCollection (see below)](#mongocollection).

### Initialization & Connecting to Meteor

Create a MeteorClient instance by passing the url to your site and optionally the version of DDP (defaults to 1) to use, then call connect to connect to the server.

```swift
let myClient = MeteorClient('wss://app.mysecuresite.com/websocket')
myClient.connect()
```

The MeteorClient uses notifications to broadcase changes in the connection, specifically

```swift    
MeteorClientDidConnect
MeteorClientConnectionReady
MeteorClientDidDisconnect
```

messages. You should register with NotificationCenter before calling connect in order to be informed of these events.

### Subscriptions

Once connected, you can manage subscriptions with:

```swift    
let subId = myClient.add(subscription: "name_of_subscription", withParams: [Any])
```

to stop a subscription (unsubscribe) call

```swift    
myClient.remove(subscriptionId: subId)
```

### CRUDing Collections

MeteorClient provides direct access to the low level insert / update / remove collection operations if they have't been forbidden on the server side, however it is better to access these directly through MongoCollection structs [see Collections below](#mongocollection-crud-operations)).

### Calling Meteor Methods

Calling methods on the Meteor server is simple. A single function is provided:

```swift    
call(method:, parameters: [], responseCallback: ? ) -> String?
```

Pass in the method name and any required parametes (these must already be in an EJSON compatible format). The function returns a methodId which can be use to monitor for a response notification, or (preferable) pass in a response callback to get the result information from the server.


### Logon

MeteorClient provides 4 login signatures as follows:

```swift    
logon(with token:, responseCallback: ?)
logonWith(username: , password:, responseCallback: ?)
logonWith(email:, password:, responseCallback: ?)
logonWith(usernameOrEmail:, password:, responseCallback: ?) 
```

The first of these expects a previous cached session token. The rest take some combination of user identifier and password to complete the logon. Each of these takes an (optional) callback once the logon call returns. The response information generally includes a session token that can be used for future logon attempts.

### OAuth

The OAuth implementation is marked experimental and is (at this time) untested. The API is defined as follow:

```swift    
logon(withOAuthAccessToken:, serviceName:, optionsKey:, responseCallback: ?) 
```    

### SignUp

There are a two functions available for creating an new account. They are:

```swift    
signup(withUsername:, email:, password:, fullname:, responseCallback: ?)
signup(withUsername:, email:, password:, firstName:, lastName:, responseCallback: ?)
```

In both of the above cases, either the username or email (not both) can be ommitted, and the name will accept and empty string.

*NOTE: In general creating a new account does NOT automatically logon to that account, instead, upon success the client should call one of the logon functions described above.*

### Collection Decoder

MeteorSwift defines the CollectionDecoder protocol which requires that a object implements decode and encode functions. These functions are passed a JSONDecoder / JSONEncoder and in order to decode/encode the object to / from EJSON. If your object also conforms to Swift's Codable then the decode / encode is trivial.

For example, with a simple object in a theoretical messaging app,

```swift    
struct Message : Codable, CollectionDecoder {
    let _id     : String
    let body    : String
    let time    : EJSONDate
}
```

*Note: the above example included a date field, and takes advantage of the MeteorSwift Codable EJSONDate type [(described below)](#ejsondate).*

conforming to CollectionDecoder is as follows:

```swift    
extension Message: CollectionDecoder {
    
    static func decode(data: Data, decoder: JSONDecoder) throws -> Any? {
        return try decoder.decode(Message.self, from: data)
    }
    
    static func encode(value: Any, encoder: JSONEncoder) throws -> Data? {
        if let message = value as? Message {
            return try encoder.encode(message)
        }
        return nil
    }
}
```

You can add additional functionality to either of these functions to perform custom actions, for example, an Image object might extract a the encoded image and create an image from it ready for use as follows:

```swift
static func decode(data: Data, decoder: JSONDecoder) throws -> Any? {
    var result = try decoder.decode(Image.self, from: data) as Image
    result.image = result.decodeImage()
    return result
}
```

You inform the MeteorClient that a particular collection supports encoding and decoding to a specific type by registering the CollectionDecoder for that collection and type as follows:

```swift    
    myClient.registerCodable("collection_name", collectionCoder: MyCollectionType.Type)
```

However, this is done automatically when you create a [MongoCollection object (see below)](#collection-decoder). Once registered in this manner, MeteorClient will automatically decode any objects sent from the server into the registered type and store them that way. If you do not register a converter, then the objects will be stored as EJSON. 

## Change Notification

It is possible to register for change notifications on a specific collection, MeteorSwift create notification names that include the action (added, removed, etc) and will post a notification through notification center whenever these actions occur. You can listen for any or all of the following.

To listen for a specific action (added, removed etc) on a specific collection, register for a notification on `collectionName_action`, to be notified of any change to a specific collection, register for a notification on `collectionName`, and to be notified of a specific action (for example all "added" events on any collection), register for a notification of `action`.

Note, this can cause a lot of notifications, so use this with care. A better approach is to register a watcher (via [MongoCollection](#watching-collections)) which will greatly reduce the the notifications that are being sent.


## EJSON

MeteorSwift provides EJSON extension structs that comply to Codable for both EJSON dates and EJSON Data. These allow you to easily encode and decode Mongo objects that include these two types.

### EJSONDate

Includes functions to retrieve the date and ms value of the EJSON encoded date as well as an initializer that takes a Swift Date() value. 

### EJSONData

Includes functions to retrieve the encoded data as a Swift Data() value. 

## MongoCollection

MongoCollection struct provides a bridge between the MeteorClient and the Collections of data it manages. The MongoCollection provides collection-level "insert", "update", "remove" functions as well as "find" and "findOne" equivalents. It also provides a way to register a "watcher" that will call you if specific objects in a collection are changed.

MongoCollection employs generics to infer the expected type of the object in the collection. If the type conforms to the CollectionDecoder protocol [(see above)](#collection-decoder), it is automatically registered with MeteorClient.

You create a MongoCollection by providing the instance of Meteor it is going to connect to, and the name of the collection as follows:

```swift    
    messages    = MongoCollection<Message>(meteor: meteor, collection: "MessageCollection")
```

### MongoCollection CRUD operations

MongoCollection implements the following CRUD operations

```swift    
    insert(object, responseCallback: callback?) -> String
    update(_id, changes: EJSONObject, responseCallback: callback?)
    remove(_id, responseCallback: callback?)
```

These pretty much do what they imply.  The first inserts a new object into the collection, automatically encoding it to EJSON before sending. The third remove an object from the collection with the matching _id, and middle one updates an object.

The update function is the only one that requires an EJSON object, and that object should have NSNull set for any fields that are being cleared. It does not update the local instance of the object, instead waiting for the server to resend the updated record as a change. Both insert and delete do make local changes accordinly. 

### Find and findOne

MongoCollection implements a find function that takes two closures, *matching* and *sorted* both of which are optional. The *matching* closure is take a single element from the collection and returns a Bool if the element should be included. This essentially filters the available records. The *sorted* closure takes two elements and returns true if the first element is greater (should be sorted after) the second. Passing nil for *matching* returns all elements, and passing nil for *sorted* returns the records in the same order as they were published.

The findOne function takes the same parameters and returns the first element of the equivalent find (or nil).

For example, to find the most recent record in the Messages collection, the following would work
 
 ```swift    
    let mostRecent = messages.findOne(match: nil) { (one, two) in 
        return first.date.ms < two.date.ms 
    }
```

### Watching Collections

MongoCollection allows you to register one or more watchers that monitor a collection for changes, each of these watchers accepts an optional *matching* closure that functions the same as with the find functions  describe above. If a record passing the *matching* closure is chaged, then the (non optional) callback closure is called with the reason for the change (inserted, insertedBefore, moved, removed, or updated), the record _id and the record itself. If the record was removed, then a copy of the record that was removed is provided.

As an example the following watches for any change to the messages collection:

```swift    
let watchId = messages.watch(matching: nil, callback: (reason, _id, message) in {
    if reason == .added {
        display(newMessage: message)
    }
}
```    

## MeteorClient Types & Protocols

MeteorSwift defines a number of helper types and protocols that are summarized below:

### Connect State Notifications

```swift    
public extension Notification {
    static let MeteorClientConnectionReady  = Notification.Name("sorr.swiftddp.ready")
    static let MeteorClientDidConnect       = Notification.Name("sorr.swiftddp.connected")
    static let MeteorClientDidDisconnect    = Notification.Name("sorr.swiftddp.disconnected")
}
```

### Client Errors

```swift    
public enum MeteorClientError:Int {
    case NotConnected
    case DisconnectedBeforeCallbackComplete
    case LogonRejected
}
```

###  OAuth Login State & Delegate

```swift    
public enum AuthState:UInt {
    case AuthStateNoAuth
    case AuthStateLoggingIn
    case AuthStateLoggedIn
    // implies using auth but not currently authorized
    case AuthStateLoggedOut
}

public protocol DDPAuthDelegate: class {
    func authenticationWasSuccessful()
    func authenticationFailed(withError: Error)
}
```

### MeteorClient Types

```swift    
public typealias EJSONObject                = [String: Any]
public typealias EJSONObjArray              = [EJSONObject]

public typealias MeteorClientMethodCallback = (DDPMessage?, Error?) -> ()
public typealias SubscriptionCallback       = (Notification.Name, String) -> Void

public protocol CollectionDecoder {
    static func decode(data: Data, decoder: JSONDecoder) throws ->  Any?
    static func encode(value: Any, encoder: JSONEncoder) throws -> Data?
}
```

### MongoCollection Types

```swift    
public typealias MeteorMatcher<T>      = (T) -> Bool
public typealias MeteorSorter<T>       = (T, T) -> Bool
public typealias CollectionCallback<T> = (ChangedReason, String, T?) -> Void

public enum ChangedReason: String {
    case added
    case addedBefore
    case movedBefore
    case removed
    case changed
}
```










