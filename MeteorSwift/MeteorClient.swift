//
//  MeteorClient.swift
//  LiveScores
//
//  Created by Stephen Orr on 2018-06-23.
//  Copyright © 2018 Stephen Orr. All rights reserved.
//

import Foundation

public extension Notification {
    static let MeteorClientConnectionReady  = Notification.Name("sorr.swiftddp.ready")
    static let MeteorClientDidConnect       = Notification.Name("sorr.swiftddp.connected")
    static let MeteorClientDidDisconnect    = Notification.Name("sorr.swiftddp.disconnected")
    static let MeteorClientUpdateSession    = Notification.Name("sorr.swiftddp.disconnected")
}

public protocol MeteorConnectionDelegate {
    func meteorDidConnect()
    func meteorDidDisconnect()
    func meteorClientReady()
    func meteorClientUpdateSession(userId: String, sessionToken: String)
}

/// Possible Errors from the Meteor Client
///
/// - NotConnected: Client is not currently connected
/// - DisconnectedBeforeCallbackComplete: Client disconnected from callback completed.
/// - LogonRejected: Logon to Meteor Client failed.
public enum MeteorClientError:Int {
    case NotConnected
    case DisconnectedBeforeCallbackComplete
    case LogonRejected
}

/// OAuth login state (experimental)
///
/// - AuthStateNoAuth: No OAuth authorization
/// - AuthStateLoggingIn: OAuth currently logging in
/// - AuthStateLoggedIn: OAuth successfully logged in
/// - AuthStateLoggedOut: OAuth is logged out
public enum AuthState:UInt {
    case AuthStateNoAuth
    case AuthStateLoggingIn
    case AuthStateLoggedIn
    // implies using auth but not currently authorized
    case AuthStateLoggedOut
}

/// Delegate for OAuth style login (experimental)
public protocol DDPAuthDelegate: class {
    func authenticationWasSuccessful()
    func authenticationFailed(withError: Error)
}

/// Helper type EJSON (JSON) object for Meteor
public typealias EJSONObject                = [String: Any]
/// Helper type array of EJSON (JSON) objects for Meteor
public typealias EJSONObjArray              = [EJSONObject]

/// Response callback for any invocation of a Meteor method
public typealias MeteorClientMethodCallback = (Result<DDPMessage, Error>) -> ()
/// Subscription callback, called when a subscription is ready
public typealias SubscriptionCallback       = (String, String) -> Void

/// Convenience type, a Meteor Collection is an ordered
/// dictionary of ids / data pairs.
typealias MeteorCollection  = OrderedDictionary<String, Any>

let MeteorClientRetryIncreaseBy = Double(1)
let MeteorClientMaxRetryIncrease = Double(6)

/// This class provide the Meteor client interface and wraps / managed
/// the DDP interface that connects to the Meteor server.
public class MeteorClient: NSObject {
    static let MeteorTransportErrorDomain   = "sorr.swiftddp.transport"
    
    var ddpVersion                  = "1"
    var ddp                         : SwiftDDP?
    
    let jsonDecoder                 = JSONDecoder()
    //
    // Raw Collections backing store
    var collections                 = [String: MeteorCollection]()
    //
    // Subscription Management
    var subscriptions               = [String: String]()
    var _subscriptionParameters     = [String: [Any]]()
    var _subscriptionCallback       = [String: SubscriptionCallback]()
    var _readySubscriptions         = [String: Bool]()
    var subscriptionGroups          = [String: [String]]()
    //
    // Method calls
    var _methodIds                  = Set<String>()
    var _responseCallbacks          = [String: MeteorClientMethodCallback]()
    //
    // Housekeeping.
    var _maxRetryIncrement          = MeteorClientMaxRetryIncrease
    var _tries                      = MeteorClientRetryIncreaseBy
    var _supportedVersions          : [String]

    public var authDelegate         : DDPAuthDelegate?
    public var connectionDelegate   : MeteorConnectionDelegate?
    
    var userId                      : String?
    var sessionToken                : String?
    var websocketReady              = false
    var connected                   = false
    var _disconnecting              = false
    var authState                   = AuthState.AuthStateNoAuth
    var codables                    = [String: CollectionDecoder.Type]()
    var _collectionWatchers         = [String: ObjectChangeLister]()

    /// Initialize the Meteor Client Object
    ///
    /// - Parameters:
    ///   - site: The URL for the site, for example
    ///         "ws://app.mysite.com/websocket"
    ///         "wss://app.mysecuresite.com/websocket"
    ///   - ddpVer: The DDP version to use, defaults to "1"
    public init(site: String, withDDPVersion ddpVer: String = "1")                                                      {
        ddpVersion = ddpVer
        if (ddpVersion == "1") {
            _supportedVersions = ["1", "pre2"]
        } else {
            _supportedVersions = ["pre2", "pre1"]
        }
        super.init()
        ddp = SwiftDDP.init(withURLString: site, delegate: self)
    }
    /// Return true if the server is currently connected.
    public var isConnected          : Bool                                                                              { return connected }
    /// Connect to the Meteor client
    public func connect()                                                                                               {
        ddp?.connectWebSocket()
    }
    /// Disconnect from the Meteor client
    public func disconnect()                                                                                            {
        _disconnecting = true
        ddp?.disconnectWebSocket()
    }
    /// Registers a Type for a Collection, that type must conform to CollectionDecoder
    /// (which in turn implies conformance with Codable). If provided, the associated
    /// collection will decode incoming EJSON records into the provided type.
    ///
    /// - Parameters:
    ///   - collection: The name of the collection to associate the decoder with
    ///   - collectionCoder: The Type to associate with the specified collection
    func register(codable: CollectionDecoder.Type, for collection: String)                                              {
        codables[collection] = codable
    }
    /// Registers a an object (typically a MeteorWatcher from MongoCollection) that will recieve
    /// update callbacks when objects are added / removed / updated to a collection.
    ///
    /// - Parameters:
    ///   - collection: The name of the collection to associate the decoder with
    ///   - collectionCoder: The Type to associate with the specified collection
    func register(watcher: ObjectChangeLister, for collection: String)                                                  {
        _collectionWatchers[collection] = watcher
    }

    /// Removes all records from all collections. leaves records that were put there from Offline storage
    public func resetCollections()                                                                                      {
        var temp = MeteorCollection()
        for (name, collection) in collections {
            temp.removeAll()
            for (key, object) in collection {
                if let entry = object as? OfflineObject, entry._wasOffline_ == true {
                    temp.add(entry, for: key)
                }
            }
            collections[name] = temp
        }
    }
    /// Provides low level insert support for a collection
    ///
    /// - Parameters:
    ///   - collectionName: The name of the collection to insert a record into.
    ///   - object: The object to insert. If the collection has an associated CollectionDecoder
    ///             then this object is first encoded to EJSON before sending.
    ///   - responseCallback: Optional callback with results of the insertion.
    /// - Returns: The _id of the new object (or nil on a failure)
    @discardableResult
    public func insert(into collectionName: String, object: Any,
                       responseCallback: MeteorClientMethodCallback? = nil) -> String?                                  {
        if var insert = ddp?.convertToEJSON(object: object) {
            //
            // Check if there is an an ID, if not create one.
            var _id = insert["_id"] as? String
            if _id == nil || _id!.isEmpty {
                _id = NSUUID().uuidString
                insert["_id"] = _id
            }
            call(method: "/\(collectionName)/insert", parameters: [object], responseCallback: responseCallback)
            
            var collection = collections[collectionName, default: MeteorCollection()]
            collection.add(object, for: _id!)
            collections[collectionName] = collection

            return _id
        }
        return nil
    }
    /// Inserts a value (typically taken from local store) into the
    /// collection with the specified id without waiting for it to come from Meteor.
    ///
    /// - Parameters:
    ///     item:   Any, should be the same type as the collection is holding.
    ///     withId: String, the mongoID of the item to insert.
    public func add(item: Any, forId _id: String, into collectionName: String)                                          {
        var collection = collections[collectionName] ?? MeteorCollection()
        collection.add(item, for: _id)
        collections[collectionName] = collection
    }
 
    /// Provides low level update support for a collection, fields
    /// set to NSNull will be cleared from the object, all other
    /// fields will be set.
    ///
    /// - Parameters:
    ///   - collectionName: The name of the collection to insert a record into.
    ///   - objectWithId: The objectId to remove.
    ///   - changes: An EJSON object with the required changes
    ///   - responseCallback: Optional callback with results of the remove.
    public func update(into collectionName: String, objectWithId _id:String, changes: EJSONObject,
                       responseCallback: MeteorClientMethodCallback? = nil)                                             {

        let cleared = changes.filter({ $1 is NSNull }).map{ $0.0 }
        var modifiers:EJSONObject =
            ["$set": changes.filter { cleared.contains($0.0) }
        ]
        if cleared.count > 0 {
            modifiers["$unset"] = Dictionary.init(uniqueKeysWithValues: cleared.map { ($0, "") })
        }
        call(method: "/\(collectionName)/update", parameters: [["_id", _id], modifiers], responseCallback: responseCallback)
    }
    /// Provides low level remove support for a collection
    ///
    /// - Parameters:
    ///   - collectionName: The name of the collection to insert a record into.
    ///   - objectWithId: The objectId to remove.
    ///   - responseCallback: Optional callback with results of the remove.
    public func remove(from collectionName: String, objectWithId _id: String,
                       responseCallback: MeteorClientMethodCallback? = nil)                                             {
        
        call(method: "/\(collectionName)/remove", parameters: [["_id", _id]], responseCallback: responseCallback)
    
        var collection = collections[collectionName, default: MeteorCollection()]
        collection.remove(key: _id)
        collections[collectionName] = collection

    }
    /// Sends a method to the Meteor server with no response / callback.
    ///
    /// - Parameters:
    ///   - methodName: Name of the method to send
    ///   - parameters: Array of EJSON parameter
    /// - Returns: A methodId for the call.
    @discardableResult
    public func send(method methodName: String, parameters: EJSONObjArray) -> String?                                   {
        
        guard okToSend else { return nil }
        
        return send(parameters:parameters, methodName:methodName)
    }
    /// Call a meteor method
    ///
    /// - Parameters:
    ///   - methodName: The name of the method to call
    ///   - parameters: Array of EJSON parameter
    ///   - responseCallback: (Optional) callback method to call once the method completes.
    /// - Returns: A methodId for the call
    @discardableResult
    public func call(method methodName: String, parameters: [Any],
                     responseCallback: MeteorClientMethodCallback? = nil) -> String?                                    {
        if rejectIfNotConnected(responseCallback: responseCallback) {
            return nil
        }
        if let methodId = send(parameters:parameters, methodName:methodName) {
            if let callback = responseCallback {
                _responseCallbacks[methodId] = callback
            }
            return methodId
        }
        return nil
    }
    /// Records a subscription for content with the Meteor server
    ///
    /// - Parameters:
    ///   - subscription: Name of the subscription
    ///   - withParameters: (Optional) parameters for the subscription
    ///   - callback: (Optional) callback to be called once the subscription is ready.
    /// - Returns: A subscriptionId which must be used to stop/remove the subscription
    public func add(subscription name: String, withParameters: [Any]? = nil,
                    callback: SubscriptionCallback? = nil) -> String?                                                   {
        let uid = DDPIdGenerator.nextId
        subscriptions[uid] = name
        if let parameters = withParameters {
            _subscriptionParameters[uid] = parameters
        }
        guard okToSend else { return nil }
        
        _readySubscriptions[uid] = false
        ddp?.subscribe(withId: uid, name: name, parameters: withParameters)
        
        if let callback = callback {
            _subscriptionCallback[uid] = callback
        }
        return uid
    }
    /// Records any array of subscriptions for content with the Meteor server
    ///
    /// - Parameters:
    ///   - subscriptions: Array of (name: String, params: [Any]?) tuples
    ///   - callback: (Optional) callback to be called once ALL of the subscriptions are ready.
    /// - Returns: A subscriptionId which must be used to stop/remove the grouped subscriptions
    public func add(subscriptions: [(name: String, params: [Any]?)],
                    callback: SubscriptionCallback? = nil) -> String?                                                   {
        
        let uid = DDPIdGenerator.nextId     // This is an id for the subscription group.
        
        let testSubs : SubscriptionCallback = { (subId) in
            //
            // Check if ALL subscriptions in this group are marked ready
            guard let subIds = self.subscriptionGroups[uid] else { return }
            for subId in subIds {
                if self._readySubscriptions[subId] == false {
                    return
                }
            }
            //
            // To get this far, all subIds in the group have been marked ready.
            // Invoke the top level callback.
            callback?(uid)
        }
        //
        // Create an array of subscriptions, each using our "group" testSubs callback
        // to see if all of the subscriptions are ready.
        var subs = [String]()
        for sub in subscriptions {
            if let subId = add(subscription: sub.name, withParameters: sub.params, callback: testSubs) {
                subs.append(subId)
            }
        }
        subscriptionGroups[uid] = subs
        return uid
    }

    /// Stop / Remove a pre-existing subscrion
    ///
    /// - Parameter uid: A subscriptionId returned by either of the add(subscription:,callback:)
    /// or add(subscriptions:,callback:)method
    public func remove(subscriptionId uid: String)                                                                      {
        guard okToSend else { return }
        //
        // Check to see if this uid references an array of subscriptions in
        // which case, remove each subscription in the array, other wise remove the
        // single subscription.
        if let subIds = subscriptionGroups[uid] {
            for subId in subIds {
                remove(subscriptionId: subId)
            }
            subscriptionGroups.removeValue(forKey: uid)
        } else {
            ddp?.unsubscribe(withId: uid)
            subscriptions.removeValue(forKey: uid)
            _subscriptionCallback.removeValue(forKey: uid)
        }
    }
    ///
    /// Get current userId (if logged in)
    public var currentUserId : String?                                                                                  {
        return userId
    }
    ///
    /// Get current session token (if logged in)
    public var currentSessionToken : String?                                                                            {
        return sessionToken
    }   
    var okToSend:Bool                                                                                                   {
        get {
            return connected
        }
    }
    /// Logon to the Meteor client using a pre-existing session token.
    ///
    /// - Parameters:
    ///   - token: A pre-existing session token
    ///   - responseCallback: A callback with the results of loggin in.
    public func logon(with token: String, responseCallback: MeteorClientMethodCallback? = nil)                          {
        sessionToken = token
        logon(withUserParameters: ["resume": sessionToken!], responseCallback: responseCallback)
    }
    /// Login to Meteor Client with a user name and password.
    ///
    /// - Parameters:
    ///   - username: The username to login with
    ///   - password: The password to login with. This will be SHA256 encoded before transmitting.
    ///   - responseCallback: (Optional) callback once login requestion completes.
    public func logonWith(username: String, password:String, responseCallback: MeteorClientMethodCallback? = nil)       {
        logon(withUserParameters: buildUserParameters(withUsername: username, password:password), responseCallback: responseCallback)
    }
    /// Login to Meteor Client with an email and password.
    ///
    /// - Parameters:
    ///   - email: The username to login with
    ///   - password: The password to login with. This will be SHA256 encoded before transmitting.
    ///   - responseCallback: (Optional) callback once login requestion completes.
    public func logonWith(email: String, password: String, responseCallback: MeteorClientMethodCallback? = nil)         {
        logon(withUserParameters: buildUserParameters(withEmail: email, password:password), responseCallback: responseCallback)
    }
    
    /// Login to Meteor Client with an email/username and password.
    ///
    /// - Parameters:
    ///   - usernameOrEmail: The username / email to login with
    ///   - password: The password to login with. This will be SHA256 encoded before transmitting.
    ///   - responseCallback: (Optional) callback once login requestion completes.
    public func logonWith(usernameOrEmail: String, password: String, responseCallback: MeteorClientMethodCallback?)     {
        logon(withUserParameters: buildUserParameters(withUsernameOrEmail: usernameOrEmail, password:password), responseCallback: responseCallback)
    }
    
    /*
     * Logs in using access token -- this breaks the current convention,
     * but the method call is dependent on some of this class's variables
     * @param serviceName service name i.e facebook, google
     * @param accessToken short-lived one-time code received, or long-lived access token for Facebook login
     * For some logins, such as Facebook, login with OAuth may only work after customizing the accounts-x packages. This is because Facebook only returns long-lived access tokens for mobile clients
     * until meteor decides to change the packages themselves.
     * use https://github.com/jasper-lu/accounts-facebook-ddp and
     *     https://github.com/jasper-lu/facebook-ddp for reference
     *
     * If an sdk only allows login returns long-lived token, modify your accounts-x package,
     * and add your package to the if(serviceName.compare("facebook")) in _buildOAuthRequestStringWithAccessToken
     */
    
    /// Experimental? Logon with an OAuth token
    ///
    /// - Parameters:
    ///   - token: OAuth token to login with
    ///   - serviceName: OAuth service to login to (i.e. facebook)
    ///   - responseCallback: (Optional) callback once login requestion completes.
    public func logon(withOAuthAccessToken token: String, serviceName: String,
                      responseCallback: MeteorClientMethodCallback?)                                                    {
        logon(withOAuthAccessToken: token, serviceName:serviceName, optionsKey:"oauth", responseCallback:responseCallback)
    }
    
    /// Experimental? Logon with an OAuth token.
    /// Some meteor servers provide a custom login handler with a custom options key.
    /// Allow client to configure the key instead of always using "oauth"
    ///
    /// - Parameters:
    ///   - token: OAuth token to login with
    ///   - serviceName: OAuth service to login to (i.e. facebook)
    ///   - optionsKey: key to use for OAuth
    ///   - responseCallback: (Optional) callback once login requestion completes.
    public func logon(withOAuthAccessToken token: String, serviceName: String, optionsKey: String,
                      responseCallback:MeteorClientMethodCallback?)                                                     {
        
        //
        // generates random secret (credentialToken)
        let url = buildOAuthRequestString(with: token, serviceName: serviceName)
        
        // callback gives an html page in string. credential token & credential secret are stored in a hidden element
        makeHTTPRequest(at: url) { callback in
            
            if let jsonData = self.handleOAuthCallback(callback: callback) {
                
                // setCredentialToken gets set to false if the call fails
                guard (jsonData["setCredentialToken"] as? Bool ?? false) else {
                    let logonError = NSError(domain: MeteorClient.MeteorTransportErrorDomain,
                                             code: MeteorClientError.LogonRejected.rawValue,
                                             userInfo: [NSLocalizedDescriptionKey: "Unable to authenticate"])
                    
                    responseCallback?(.failure(logonError))
                    return
                }
                
                let options = [optionsKey:
                    ["credentialToken": jsonData["credentialToken"] as! String,
                     "credentialSecret": jsonData["credentialSecret"] as! String]]
                
                self.logon(withUserParameters: options, responseCallback: responseCallback)
            }
        }
    }
    /// Signup (create a new account) with full details
    ///
    /// - Parameters:
    ///   - user: user name for new account
    ///   - email: email for new account
    ///   - password: password for new account
    ///   - fullname: name of user (for profile)
    ///   - responseCallback: (Optional) callback once login requestion completes.
    public func signup(withUsername user: String = "", email: String = "", password: String,
                fullname: String, responseCallback: MeteorClientMethodCallback?)                                        {
        
        guard (!user.isEmpty || !email.isEmpty) && !password.isEmpty else {
            let userInfo = [NSLocalizedDescriptionKey: "You must provide one or both of user name and email address and a password"]
            let signUpError = NSError(domain: MeteorClient.MeteorTransportErrorDomain,
                                      code: MeteorClientError.LogonRejected.rawValue,
                                      userInfo:userInfo)

            responseCallback?(.failure(signUpError))
            return
        }
        let params = buildUserParametersSignup(username:user, email:email, password:password, fullname:fullname)
        signup(withUserParameters: params, responseCallback:responseCallback)
    }
    /// Signup (create a new account) with full details
    ///
    /// - Parameters:
    ///   - user: user name for new account
    ///   - email: email for new account
    ///   - password: password for new account
    ///   - firstName: first name of user (for profile)
    ///   - lastName: last name of user (for profile)
    ///   - responseCallback: (Optional) callback once login requestion completes.
    public func signup(withUsername user: String = "", email: String = "", password: String,
                firstName: String, lastName: String, responseCallback: MeteorClientMethodCallback?)                     {
    
        guard (!user.isEmpty || !email.isEmpty) && !password.isEmpty else {
            let userInfo = [NSLocalizedDescriptionKey: "You must provide one or both of user name and email address and a password"]
            let signUpError = NSError(domain: MeteorClient.MeteorTransportErrorDomain,
                                      code: MeteorClientError.LogonRejected.rawValue,
                                      userInfo:userInfo)
            
            responseCallback?(.failure(signUpError))
            return
        }
        let params = buildUserParametersSignup(username:user, email:email, password:password, firstName: firstName, lastName:lastName)
        signup(withUserParameters: params, responseCallback:responseCallback)
    }
    
    /// Logout of current session.
    public func logout()                                                                                                {
        ddp?.method(withId: DDPIdGenerator.nextId, method: "logout", parameters:nil)
        setAuthStatetoLoggedOut()
    }
    func reconnect()                                                                                                    {
        guard let ddp = ddp, ddp.socketNotOpen else {
            return
        }
        ddp.connectWebSocket()
    }
    
    // MARK - Internal
    func send(parameters: [Any]?, methodName: String) -> String?                                                        {
        let methodId = DDPIdGenerator.nextId
        ddp?.method(withId: methodId, method:methodName, parameters:parameters)
        return methodId
    }

    func resetBackoff()                                                                                                 {
        _tries = 1
    }
    func handleConnectionError()                                                                                        {
        websocketReady = false
        connected = false
        invalidateUnresolvedMethods()
        connectionDelegate?.meteorDidDisconnect()
        NotificationCenter.default.post(name: Notification.MeteorClientDidDisconnect, object:self)
        if _disconnecting {
            _disconnecting = false
            return
        }
        //
        let timeInterval = Double(5.0 * _tries)
        
        if (_tries != _maxRetryIncrement) {
            _tries += 1
        }
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + timeInterval) {
            self.reconnect()
        }
    }
    func invalidateUnresolvedMethods()                                                                                  {
        let error = NSError(domain: MeteorClient.MeteorTransportErrorDomain,
                            code: MeteorClientError.DisconnectedBeforeCallbackComplete.rawValue,
                            userInfo: [NSLocalizedDescriptionKey: "You were disconnected"])
        for methodId in _methodIds {
            _responseCallbacks[methodId]?(.failure(error))
        }
        _methodIds.removeAll()
        _responseCallbacks.removeAll()
    }
    func makeMeteorDataSubscriptions()                                                                                  {
        for (uid, name) in subscriptions {
            let params = _subscriptionParameters[uid]
            _readySubscriptions[uid] = false
            ddp?.subscribe(withId: uid, name: name, parameters:params)
        }
    }
    func rejectIfNotConnected(responseCallback: MeteorClientMethodCallback?) -> Bool                                    {
        guard okToSend else {
            let userInfo = [NSLocalizedDescriptionKey: "You are not connected"]
            let notConnectedError = NSError(domain: MeteorClient.MeteorTransportErrorDomain,
                                            code: MeteorClientError.NotConnected.rawValue,
                                            userInfo:userInfo)
            responseCallback?(.failure(notConnectedError))
            return true
        }
        return false
    }
    
}
