# MeteorSwift

MeteorSwift is a swift (and swifty) re-implementaion of [Objective-DDP](https://github.com/boundsj/ObjectiveDDP), that also takes advantage of Swift closures, codable types and some other Swift magic.

## Installation 
Install via CocoaPods:

`pod 'MeteorSwift'


MeteorSwift provides a small number of key classes and a number of typealiases to make everything make sense. Here is an overview

## MeteorClient

This class provides the client side implementation for a Meteor implementation.  This includes methods to login, signin, manage subscriptions, make method calls and CRUD Mongo Collections. Direct access to the collection is NOT supported via the MeteorClient, but is instead managed via the MongoCollection struct type (see below).

### Initialization & Connecting to Meteor

Create a MeteorClient instance by passing the url to your site and optionally the version of DDP (defaults to 1) to use, then call connect to connect to the server.

`   let myClient = MeteorClient('wss://app.mysecuresite.com/websocket')`
`   myClient.connect()`

The MeteorClient uses notifications to broadcase changes in the connection, specifically

`    MeteorClientDidConnect`
`    MeteorClientConnectionReady`
`    MeteorClientDidDisconnect`

messages. You should register with NotificationCenter before calling connect in order to be informed of these events.

### Subscriptions

Once connected, you can manage subscriptions with:

`let subId = myClient.add(subscription: "name_of_subscription", withParams: [Any])`

to stop a subscription (unsubscribe) call

`myClient.remove(subscriptionId: subId)`

### Login & SignUp

To Be Written

### CRUDing Collections

MeteorClient provides direct access to the low level insert / update / remove collection operations if they have't been forbidden on the server side, however it is better to access these directly through MongoCollection structs (see Collections below).

### CollectionDecoder

MeteorSwift defines the CollectionDecoder protocol which requires that an object implements the MeteorDecoder and MeteorEncoder methods. These methods are passed a JSONDecoder or JSONEncoder and are expected to decode/encode the object. To / from EJSON. If your objects also conform to Swift's Codable then the decode / encode is trivial.

For example, with a simple object in a theorietical messaging app,

`struct Message : Codable, CollectionDecoder {`
`    let _id     : String`
`    let body    : String`
`    let time    : EJSONDate`
`}`

conforming to CollectionDecoder is as follows:

`extension Message: CollectionDecoder { `
`   static let decode: MeteorDecoder = {`
`       return try $1.decode(Message.self, from: $0)`
`   }`
`   static let encode: MeteorEncoder = {`
`       if let message = $0 as? Message {`
`           return try $1.encode(message)`
`       }`
`       return nil`
`   }`
`}`

You inform the MeteorClient that a particular collection supports encodign and decoding to a specific type by registering the CollectionDecoder for that collection and type as follows:

`myClient.registerCodable("collection_name", collectionCoder: MyCollectionType.Type)`

Once registered in this manner, MeteorClient will automatically decode any objects sent from the server into the registered type and store them that way. If you do not register a converter, then the objects will be stored as EJSON. 

Note: the above example included a date field, and takes advantage of the MeteorSwift Codable EJSONDate type (described below).

## EJSON

MeteorSwift provides EJSON extension structs that comply to Codable for both EJSON dates and EJSON Data. These allow you to easily encode and decode Mongo objects that include these two types.

### EJSONDate

Includes methods to retrieve the date and ms value of the EJSON encoded date as well as an initializer that takes a Date value. 

### EJSONData

Includes methods to retrieve the encoded data as a Data() value. 

## MongoCollection

MongoCollection  provides a bridge between the MeteorClient and the Collections of data it manages. The Mongo Client provides collection-level "insert", "update", "remove" methods as well as "find" and "findOne" equivalents. MongoCollection also provides a way to register a "watcher" that will call you if selected objects in a collection are changed.

MongoCollections employ generics to infer the expected type of the object in the collection

You create a Mongo collection collection by providing the instance of Meteor it is going to connect to, and the name of the collection. 















