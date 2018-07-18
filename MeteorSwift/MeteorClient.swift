//
//  MeteorClient.swift
//  LiveScores
//
//  Created by Stephen Orr on 2018-06-23.
//  Copyright © 2018 Stephen Orr. All rights reserved.
//

import Foundation
import SocketRocket
import SCrypto

public extension Notification {
    static let MeteorClientConnectionReady  = Notification.Name("sorr.swiftddp.ready")
    static let MeteorClientDidConnect       = Notification.Name("sorr.swiftddp.connected")
    static let MeteorClientDidDisconnect    = Notification.Name("sorr.swiftddp.disconnected")
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


/// Helper type EJSON (JSON) object
public typealias EJSONObject                = [String: Any]
/// Helper type array of EJSON (JSON) objects
public typealias EJSONObjArray              = [EJSONObject]

/// Response callback for any invocation of a Meteor method
public typealias MeteorClientMethodCallback = (DDPMessage?, Error?) -> ()
/// Subscription callback, called when a subscription is ready
public typealias SubscriptionCallback       = (Notification.Name, String) -> Void
/// Codable decoder method (see CollectionDecoder)
public typealias MeteorDecoder              = (Data, JSONDecoder) throws ->  Any?
/// Codable encoder method (see CollectionDecoder)
public typealias MeteorEncoder              = (Any, JSONEncoder) throws -> Data?
/// CollectionDecoder
///
/// Allows the client to register Swift types that comply to the Codable
/// protocol and also implent the encode and decode helper methods to convert
/// EJSON objects into structures or classes. If provided the collections
/// managed by Meteor will contain concrete types rather than JSONObjects.
public protocol CollectionDecoder {
    static var decode: MeteorDecoder { get }
    static var encode: MeteorEncoder { get }
}

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
    let jsonEncoder                 = JSONEncoder()

    var collections                 = [String: MeteorCollection]()
    var subscriptions               = [String: String]()
    var _subscriptionsParameters    = [String: [Any]]()
    var _subscriptionCallback       = [String: SubscriptionCallback]()
    var _methodIds                  = Set<String>()
    var _responseCallbacks          = [String: MeteorClientMethodCallback]()
    var _maxRetryIncrement          = MeteorClientMaxRetryIncrease
    var _tries                      = MeteorClientRetryIncreaseBy
    var _supportedVersions          : [String]

    var authDelegate                : DDPAuthDelegate?
    var userId                      : String?
    var sessionToken                : String?
    var websocketReady              = false
    var connected                   = false
    var _disconnecting              = false
    var authState                   = AuthState.AuthStateNoAuth
    var codables                    = [String: CollectionDecoder.Type]()
    
    /// Initialize the Meteor Client Object
    ///
    /// - Parameters:
    ///   - site: The URL for the site, for example
    ///         "ws://app.mysite.com/websocket"
    ///         "wss://app.mysecuresite.com/websocket"
    ///   - ddpVer: The DDP version to use, defaults to "1"
    public init(site: String, withDDPVersion ddpVer: String = "1") {
        ddpVersion = ddpVer
        if (ddpVersion == "1") {
            _supportedVersions = ["1", "pre2"]
        } else {
            _supportedVersions = ["pre2", "pre1"]
        }
        super.init()
        ddp = SwiftDDP.init(withURLString: site, delegate: self)
    }
    /// Connect to the Meteor client
    public func connect() {
        ddp?.connectWebSocket()
    }
    /// Disconnect from the Meteor client
    public func disconnect() {
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
    public func registerCodable(_ collection: String, collectionCoder: CollectionDecoder.Type) {
        codables[collection] = collectionCoder
    }
    /// Removes all records from all collections
    public func resetCollections() {
        collections.removeAll()
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
    public func insert(into collectionName: String, object: Any, responseCallback: MeteorClientMethodCallback? = nil) -> String? {
        if var insert = convertToEJSON(collection: collectionName, object: object) {
            //
            // Check if there is an an ID, if not create one.
            var _id = insert["_id"] as? String
            if _id == nil || _id!.isEmpty {
                _id = NSUUID().uuidString
                insert["_id"] = _id
            }
            call(method: "/\(collectionName)/insert", parameters: [insert], responseCallback: responseCallback)
            //
            // TODO: Insert it locally as well
            
            return _id
        }
        return nil
    }
    /// Provides low level insert support for a collection
    ///
    /// - Parameters:
    ///   - collectionName: The name of the collection to insert a record into.
    ///   - objectWithId: The objectId to remove.
    ///   - responseCallback: Optional callback with results of the remove.
    public func remove(from collectionName: String, objectWithId _id: String, responseCallback: MeteorClientMethodCallback?) {
        call(method: "/\(collectionName)/remove", parameters: [["_id", _id]], responseCallback: responseCallback)
    }
    /// Sends a method to the Meteor server with an option to post a notification
    /// when the method response is received.
    ///
    /// - Parameters:
    ///   - methodName: Name of the method to send
    ///   - parameters: Array of EJSON parameter
    ///   - notifyOnResponse: Defaults to false if no notification is required
    /// - Returns: A methodId for the call.
    @discardableResult
    public func send(method methodName: String, parameters: EJSONObjArray, notifyOnResponse: Bool = false) -> String? {
        
        guard okToSend else { return nil }
        
        return send(notify: notifyOnResponse, parameters:parameters, methodName:methodName)
    }
    /// Call a meteor method
    ///
    /// - Parameters:
    ///   - methodName: The name of the method to call
    ///   - parameters: Array of EJSON parameter
    ///   - responseCallback: (Optional) callback method to call once the method completes.
    /// - Returns: A methodId for the call
    @discardableResult
    public func call(method methodName: String, parameters: [Any], responseCallback: MeteorClientMethodCallback? = nil) -> String? {
        if rejectIfNotConnected(responseCallback: responseCallback) {
            return nil
        }
        let methodId = send(notify: true, parameters:parameters, methodName:methodName)
        if let callback = responseCallback, let methodId = methodId {
            _responseCallbacks[methodId] = callback
        }
        return methodId
    }
    /// Records a subscription for content with the Meteor server
    ///
    /// - Parameters:
    ///   - name: Name of the subscription
    ///   - withParameters: (Optional) parameters for the subscription
    ///   - callback: (Optional) callback to be called once the subscription is ready.
    /// - Returns: A subscriptionId which must be used to stop/remove the subscription
    public func add(subscription name: String, withParameters: [Any]? = nil, callback: SubscriptionCallback? = nil) -> String? {
        let uid = DDPIdGenerator.nextId
        subscriptions[uid] = name
        if let parameters = withParameters {
            _subscriptionsParameters[uid] = parameters
        }
        guard okToSend else { return nil }
        
        ddp?.subscribe(withId: uid, name: name, parameters: withParameters)
        
        if let callback = callback {
            _subscriptionCallback[uid] = callback
        }
        return uid
    }
    /// Stop / Remove a pre-existing subscrion
    ///
    /// - Parameter uid: The subscriptionId return by the add(subscription:) method
    public func remove(subscriptionId uid: String) {
        guard okToSend else { return }
        ddp?.unsubscribe(withId: uid)
        subscriptions.removeValue(forKey: uid)
        _subscriptionCallback.removeValue(forKey: uid)
    }
    var okToSend:Bool {
        get {
            return connected
        }
    }
    
    // tokenExpires.$date : expiry date
    /// Logon to the Meteor client using a pre-existing session token.
    ///
    /// - Parameters:
    ///   - token: A pre-existing session token
    ///   - responseCallback: A callback with the results of loggin in.
    public func logon(with token: String, responseCallback: MeteorClientMethodCallback?) {
        sessionToken = token
        setAuthStateToLoggingIn()
        call(method: "login", parameters: ["resume", sessionToken!]) {
            if let error = $1 {
                self.setAuthStatetoLoggedOut()
                self.authDelegate?.authenticationFailed(withError: error)
                
            } else if let result = $0?["result"] as? EJSONObject {
                self.setAuthStateToLoggedIn(userId: result["id"] as! String, withToken: result["token"] as! String)
                self.authDelegate?.authenticationWasSuccessful()
            }
            responseCallback?($0, $1)
        }
    }
    
    public func logonWith(username: String, password:String, responseCallback: MeteorClientMethodCallback? = nil) {
        logon(withUserParameters: buildUserParameters(withUsername: username, password:password), responseCallback: responseCallback)
    }
    
    public func logonWith(email: String, password: String, responseCallback: MeteorClientMethodCallback? = nil) {
        logon(withUserParameters: buildUserParameters(withEmail: email, password:password), responseCallback: responseCallback)
    }
    
    public func logonWith(usernameOrEmail: String, password: String, responseCallback: MeteorClientMethodCallback?) {
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
    public func logon(withOAuthAccessToken token: String, serviceName: String, responseCallback: MeteorClientMethodCallback?) {
        logon(withOAuthAccessToken: token, serviceName:serviceName, optionsKey:"oauth", responseCallback:responseCallback)
    }
    
    // some meteor servers provide a custom login handler with a custom options key. Allow client to configure the key instead of always using "oauth"
    public func logon(withOAuthAccessToken token: String, serviceName: String, optionsKey: String, responseCallback:MeteorClientMethodCallback?) {
        
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
                    
                    responseCallback?(nil, logonError)
                    return
                }
                
                let options = [optionsKey:
                    ["credentialToken": jsonData["credentialToken"] as! String,
                     "credentialSecret": jsonData["credentialSecret"] as! String]]
                
                self.logon(withUserParameters: options, responseCallback: responseCallback)
            }
        }
    }
    
    private func logon(withUserParameters: EJSONObject, responseCallback: MeteorClientMethodCallback?) {
        guard authState != .AuthStateLoggingIn else {
            let errorDesc = "You must wait for the current logon request to finish before sending another."
            let logonError = NSError(domain: MeteorClient.MeteorTransportErrorDomain,
                                     code: MeteorClientError.LogonRejected.rawValue,
                                     userInfo: [NSLocalizedDescriptionKey: errorDesc])
            responseCallback?(nil, logonError)
            return
        }
        
        guard !rejectIfNotConnected(responseCallback: responseCallback) else {
            return
        }
        
        setAuthStateToLoggingIn()
        
        call(method: "login", parameters: [withUserParameters]) {
            if let error = $1 {
                self.setAuthStatetoLoggedOut()
                self.authDelegate?.authenticationFailed(withError: error)
            } else if let response = $0 as? EJSONObject {
                // tokenExpires.$date : expiry date
                if let result = response["result"] as? EJSONObject {
                    self.setAuthStateToLoggedIn(userId: result["id"] as! String, withToken: result["token"] as! String)
                    self.authDelegate?.authenticationWasSuccessful()
                }
            }
            responseCallback?($0, $1)
        }
    }
    
    func signup(withUsername user: String = "", email: String = "", password: String,
                fullname: String, responseCallback: MeteorClientMethodCallback?) {
        
        guard (!user.isEmpty || !email.isEmpty) && !password.isEmpty else {
            let userInfo = [NSLocalizedDescriptionKey: "You must provide one or both of user name and email address and a password"]
            let signUpError = NSError(domain: MeteorClient.MeteorTransportErrorDomain,
                                      code: MeteorClientError.LogonRejected.rawValue,
                                      userInfo:userInfo)

            responseCallback?(nil, signUpError)
            return
        }
        let params = buildUserParametersSignup(username:user, email:email, password:password, fullname:fullname)
        signup(withUserParameters: params, responseCallback:responseCallback)
    }
    
    func signup(withUsername user: String = "", email: String = "", password: String,
                firstName: String, lastName: String, responseCallback: MeteorClientMethodCallback?) {
    
        guard (!user.isEmpty || !email.isEmpty) && !password.isEmpty else {
            let userInfo = [NSLocalizedDescriptionKey: "You must provide one or both of user name and email address and a password"]
            let signUpError = NSError(domain: MeteorClient.MeteorTransportErrorDomain,
                                      code: MeteorClientError.LogonRejected.rawValue,
                                      userInfo:userInfo)
            
            responseCallback?(nil, signUpError)
            return
        }
        let params = buildUserParametersSignup(username:user, email:email, password:password, firstName: firstName, lastName:lastName)
        signup(withUserParameters: params, responseCallback:responseCallback)
    }
    
    func signup(withUserParameters params:EJSONObject, responseCallback: MeteorClientMethodCallback?) {
        
        guard authState != .AuthStateLoggingIn else {
            let errorDesc = "You must wait for the current signup request to finish before sending another."
            let logonError = NSError(domain: MeteorClient.MeteorTransportErrorDomain,
                                     code:MeteorClientError.LogonRejected.rawValue,
                                     userInfo: [NSLocalizedDescriptionKey: errorDesc])
            authDelegate?.authenticationFailed(withError: logonError)
            responseCallback?(nil, logonError)
            return
        }
        setAuthStateToLoggingIn()
        
        call(method: "createUser", parameters: [params]) {
            
            if let error = $1 {
                self.setAuthStatetoLoggedOut()
                self.authDelegate?.authenticationFailed(withError: error)
            } else if let result = $0?["result"] as? EJSONObject {
                self.setAuthStateToLoggedIn(userId: result["id"] as! String, withToken: result["token"]  as! String)
                self.authDelegate?.authenticationWasSuccessful()
            }
            responseCallback?($0, $1)
        }
    }
        
    func logout() {
        ddp?.method(withId: DDPIdGenerator.nextId, method: "logout", parameters:nil)
        setAuthStatetoLoggedOut()
    }
    
    @objc func reconnect() {
        guard ddp?.socketState != SRReadyState.OPEN else {
            return
        }
        ddp?.connectWebSocket()
    }
    
    func ping() {
        guard connected else {
            return
        }
        ddp?.ping(id: DDPIdGenerator.nextId)
    }
    
    // MARK - Internal
    private func send(notify: Bool, parameters: [Any]?, methodName: String) -> String? {
        let methodId = DDPIdGenerator.nextId
        if notify {
            _methodIds.insert(methodId)
        }
        ddp?.method(withId: methodId, method:methodName, parameters:parameters)
        return methodId
    }
    
    fileprivate func resetBackoff() {
        _tries = 1
    }
    
    fileprivate func handleConnectionError() {
        websocketReady = false
        connected = false
        invalidateUnresolvedMethods()
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
        perform(#selector(reconnect), with:self, afterDelay:timeInterval)
    }
    
    func invalidateUnresolvedMethods() {
        for methodId in _methodIds {
            if let callback = _responseCallbacks[methodId] {
                callback(nil, NSError(domain: MeteorClient.MeteorTransportErrorDomain,
                                    code: MeteorClientError.DisconnectedBeforeCallbackComplete.rawValue,
                                    userInfo: [NSLocalizedDescriptionKey: "You were disconnected"]))
            }
        }
        _methodIds.removeAll()
        _responseCallbacks.removeAll()
    }
    
    fileprivate func makeMeteorDataSubscriptions() {
        for (uid, name) in subscriptions {
            let params = _subscriptionsParameters[uid]
            ddp?.subscribe(withId: uid, name: name, parameters:params)
        }
    }
    
    private func rejectIfNotConnected(responseCallback: MeteorClientMethodCallback?) -> Bool {
        guard okToSend else {
            let userInfo = [NSLocalizedDescriptionKey: "You are not connected"]
            let notConnectedError = NSError(domain: MeteorClient.MeteorTransportErrorDomain,
                                            code: MeteorClientError.NotConnected.rawValue,
                                            userInfo:userInfo)
            responseCallback?(nil, notConnectedError)
            return true
        }
        return false
    }
    
    private func setAuthStateToLoggingIn() {
        authState = .AuthStateLoggingIn
    }
    
    private func setAuthStateToLoggedIn(userId id: String, withToken: String) {
        authState = .AuthStateLoggedIn
        userId = id
        sessionToken = withToken
    }
    
    private func setAuthStatetoLoggedOut() {
        authState = .AuthStateLoggedOut
        userId = nil
    }
    
    func convertToEJSON(collection name:String, object: Any) -> EJSONObject? {
        if let collectionCoder = codables[name] {
            do {
                if let data = try collectionCoder.encode(object, jsonEncoder) {
                    //
                    // Merge changes into the original object.
                    let encoded = try JSONSerialization.jsonObject(with: data, options: [])
                    if let result = encoded as? EJSONObject {
                        return result
                    } else {
                        print("MeteorSwift: Encoded element in \(name) is not EJSONObject")
                    }
                }
            } catch {
                print("MeteorSwift: Failed to encode element in \(name) - reported error \(error.localizedDescription)")
            }
        }
        if let result = object as? EJSONObject {
            return result
        }
        return nil
    }
    func buildUserParametersSignup(username:String, email: String, password: String, fullname: String) -> EJSONObject {
        return ["username": username, "email": email,
                "password": [ "digest": password.SHA256(), "algorithm": "sha-256" ],
                "profile": ["fullname": fullname, "signupToken": ""]]
    }
    
    func buildUserParametersSignup(username:String, email:String, password:String,
                                   firstName: String, lastName:String) -> EJSONObject {
        
        return ["username": username, "email": email,
                "password": [ "digest": password.SHA256(), "algorithm": "sha-256" ],
                "profile": ["first_name": firstName, "last_name": lastName,"signupToken": ""]]
    }
    
    func buildUserParameters(withUsername: String, password: String) -> EJSONObject   {
        return ["user": ["username": withUsername], "password": ["digest": password.SHA256(), "algorithm": "sha-256" ]]
    }
    
    private func buildUserParameters(withEmail: String, password: String) -> EJSONObject    {
        return ["user": ["email": withEmail], "password": ["digest": password.SHA256(), "algorithm": "sha-256" ]]
    }
    
    private func buildUserParameters(withUsernameOrEmail: String, password: String) -> EJSONObject   {
        if withUsernameOrEmail.contains("@") {
            return buildUserParameters(withEmail:withUsernameOrEmail, password:password)
        } else {
            return buildUserParameters(withUsername:withUsernameOrEmail, password:password)
        }
    }
    
    func buildOAuthRequestString(with accessToken:String, serviceName: String) -> String    {
        
        if var homeUrl = ddp?.url {
            homeUrl = homeUrl.replacingOccurrences(of: "/websocket", with: "")
            //remove ws/wss and replace with http/https
            if homeUrl.starts(with: "ws/") {
                homeUrl = "http" + homeUrl.dropFirst(2)
            } else {
                homeUrl = "https" + homeUrl.dropFirst(3)
            }
            
            var tokenType = ""
            //
            // facebook sdk can only send access token, others send a one time code
            if serviceName == "facebook" {
                tokenType = "accessToken"
            } else {
                tokenType = "code"
            }
            let state = generateState(withToken: randomSecret())
            
            return "\(homeUrl)/_oauth/\(serviceName)/?\(tokenType)=\(accessToken)&state=\(state)"
        }
        return ""
    }
    
    func buildUserParameters(withOAuthAccessToken: String) -> EJSONObject {
        return EJSONObject()
    }
    
    //functions for OAuth
    
    //generates base64 string for json
    func generateState(withToken: String) -> String {
        if let jsonData = try? JSONSerialization.data(withJSONObject: ["credentialToken": withToken, "loginStyle": "popup"], options: []) {

            return jsonData.base64EncodedString(options: .endLineWithLineFeed)
        }
        return ""
    }
    
    //generates random secret for credential token
    private func randomSecret() -> String {
        let BASE64_CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_" as NSString
        let s = NSMutableString(capacity:20)
        for _ in 0..<20 {
            let r = Int(arc4random() % UInt32(BASE64_CHARS.length))
            let c = BASE64_CHARS.character(at: r)
            s.appendFormat("%C", c)
        }
        return s as String
    }
    
    func makeHTTPRequest(at url: String, completion: @escaping (String?) -> Void ) {
        guard let url = URL(string: url) else {
            completion(nil)
            return
        }
        
        let request = NSMutableURLRequest(url: url)
        request.httpMethod = "GET"
        
        URLSession.shared.dataTask(with: request as URLRequest, completionHandler:{ (data, response, error) in
            DispatchQueue.main.async {
                if let error = error {
                    print("MeteorSwift: Error getting \(url), Error: \(error)")
                } else {
                    if let code = response as? HTTPURLResponse {
                        guard code.statusCode == 200 else {
                            print("MeteorSwift: Error getting \(url), HTTP status code \(code.statusCode)")
                            completion(nil)
                            return
                        }
                        if let data = data {
                            completion(String(data: data, encoding: .utf8))
                        }
                    }
                }
                completion(nil)
            }
        }).resume()
    }
        
    func handleOAuthCallback(callback:String?) -> EJSONObject? {
        // it's possible callback is nil
       
        guard var callback = callback else {
            return nil
        }
        if let regex = try? NSRegularExpression(pattern: "<div id=\"config\" style=\"display:none;\">(.*?)</div>") {
            
            let range = regex.rangeOfFirstMatch(in: callback, range: NSRange(0..<callback.count))
            callback = String(callback[Range(range, in: callback)!])
            
            return try? JSONSerialization.jsonObject(with: callback.data(using: .utf8)!, options: []) as! EJSONObject
        }
        return nil
    }
}

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
            NotificationCenter.default.post(name: Notification.MeteorClientConnectionReady, object:self)
            if let sessionToken = sessionToken { //TODO check expiry date
                logon(with: sessionToken, responseCallback: nil)
            }
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
        NotificationCenter.default.post(name: Notification.MeteorClientDidConnect, object: self)
    }
    func didReceive(connectionError: Error) {
        handleConnectionError()
    }
    func didReceiveConnectionClose() {
        handleConnectionError()
    }
}
