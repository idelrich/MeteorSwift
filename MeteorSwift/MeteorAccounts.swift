//
//  MeteorAccounts.swift
//  MeteorSwift
//
//  Created by Stephen Orr on 2018-07-18.
//  Copyright © 2018 Stephen Orr. All rights reserved.
//

import Foundation

extension MeteorClient { // Accounts
    func logon(withUserParameters: EJSONObject, responseCallback: MeteorClientMethodCallback?)                          {
        guard authState != .AuthStateLoggingIn else {
            let errorDesc = "You must wait for the current logon request to finish before sending another."
            let logonError = NSError(domain: MeteorClient.MeteorTransportErrorDomain,
                                     code: MeteorClientError.LogonRejected.rawValue,
                                     userInfo: [NSLocalizedDescriptionKey: errorDesc])
            responseCallback?(.failure(logonError))
            return
        }
        
        guard !rejectIfNotConnected(responseCallback: responseCallback) else {
            return
        }
        setAuthStateToLoggingIn()
        
        call(method: "login", parameters: [withUserParameters]) {
            switch $0 {
            case .success(let response):
                // tokenExpires.$date : expiry date
                if let result = response["result"] as? EJSONObject {
                    self.setAuthStateToLoggedIn(userId: result["id"] as! String, withToken: result["token"] as! String)
                    self.authDelegate?.authenticationWasSuccessful()
                }

            case .failure(let error):
                self.setAuthStatetoLoggedOut()
                self.authDelegate?.authenticationFailed(withError: error)
            }
            responseCallback?($0)
        }
    }
    func signup(withUserParameters params:EJSONObject, responseCallback: MeteorClientMethodCallback?)                   {
        
        guard authState != .AuthStateLoggingIn else {
            let errorDesc = "You must wait for the current signup request to finish before sending another."
            let logonError = NSError(domain: MeteorClient.MeteorTransportErrorDomain,
                                     code:MeteorClientError.LogonRejected.rawValue,
                                     userInfo: [NSLocalizedDescriptionKey: errorDesc])
            authDelegate?.authenticationFailed(withError: logonError)
            responseCallback?(.failure(logonError))
            return
        }
        setAuthStateToLoggingIn()
        
        call(method: "createUser", parameters: [params]) {
            
            switch $0 {
            case .success(let response):
                // tokenExpires.$date : expiry date
                if let result = response["result"] as? EJSONObject {
                    self.setAuthStateToLoggedIn(userId: result["id"] as! String, withToken: result["token"] as! String)
                    self.authDelegate?.authenticationWasSuccessful()
                }

            case .failure(let error):
                self.setAuthStatetoLoggedOut()
                self.authDelegate?.authenticationFailed(withError: error)
            }
            responseCallback?($0)
        }
    }
    func setAuthStateToLoggingIn()                                                                                      {
        authState = .AuthStateLoggingIn
    }
    func setAuthStateToLoggedIn(userId id: String, withToken: String)                                                   {
        authState = .AuthStateLoggedIn
        userId = id
        sessionToken = withToken
        NotificationCenter.default.post(name: Notification.MeteorClientUpdateSession, object:self)
        connectionDelegate?.meteorClientUpdateSession(userId: id, sessionToken: withToken)
    }
    func setAuthStatetoLoggedOut()                                                                                      {
        authState = .AuthStateLoggedOut
        userId = nil
    }
    
    func buildUserParametersSignup(username:String, email: String, password: String, fullname: String) -> EJSONObject   {
        return ["username": username, "email": email,
                "password": [ "digest": password.sha256(), "algorithm": "sha-256" ],
                "profile": ["fullname": fullname, "signupToken": ""]]
    }
    func buildUserParametersSignup(username:String, email:String, password:String,
                                   firstName: String, lastName:String) -> EJSONObject                                   {
        
        return ["username": username, "email": email,
                "password": [ "digest": password.sha256(), "algorithm": "sha-256" ],
                "profile": ["first_name": firstName, "last_name": lastName,"signupToken": ""]]
    }
    func buildUserParameters(withUsername: String, password: String) -> EJSONObject                                     {
        return ["user": ["username": withUsername], "password": ["digest": password.sha256(), "algorithm": "sha-256" ]]
    }
    func buildUserParameters(withEmail: String, password: String) -> EJSONObject                                        {
        return ["user": ["email": withEmail], "password": ["digest": password.sha256(), "algorithm": "sha-256" ]]
    }
    func buildUserParameters(withUsernameOrEmail: String, password: String) -> EJSONObject                              {
        if withUsernameOrEmail.contains("@") {
            return buildUserParameters(withEmail:withUsernameOrEmail, password:password)
        } else {
            return buildUserParameters(withUsername:withUsernameOrEmail, password:password)
        }
    }
    func buildOAuthRequestString(with accessToken:String, serviceName: String) -> String                                {
        
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
    
    func buildUserParameters(withOAuthAccessToken: String) -> EJSONObject                                               {
        return EJSONObject()
    }
    
    // functions for OAuth
    
    // generates base64 string for json
    func generateState(withToken: String) -> String                                                                     {
        if let jsonData = try? JSONSerialization.data(withJSONObject: ["credentialToken": withToken, "loginStyle": "popup"], options: []) {
            
            return jsonData.base64EncodedString(options: .endLineWithLineFeed)
        }
        return ""
    }
    // generates random secret for credential token
    func randomSecret() -> String                                                                                       {
        let BASE64_CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_" as NSString
        let s = NSMutableString(capacity:20)
        for _ in 0..<20 {
            let r = Int(arc4random() % UInt32(BASE64_CHARS.length))
            let c = BASE64_CHARS.character(at: r)
            s.appendFormat("%C", c)
        }
        return s as String
    }
    func makeHTTPRequest(at url: String, completion: @escaping (String?) -> Void )                                      {
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
    func handleOAuthCallback(callback:String?) -> EJSONObject?                                                          {
        // it's possible callback is nil
        
        guard var callback = callback                               else { return nil }
        
        if let regex = try? NSRegularExpression(pattern: "<div id=\"config\" style=\"display:none;\">(.*?)</div>") {
            
            let range = regex.rangeOfFirstMatch(in: callback, range: NSRange(0..<callback.count))
            callback = String(callback[Range(range, in: callback)!])
            
            return try? JSONSerialization.jsonObject(with: callback.data(using: .utf8)!, options: []) as? EJSONObject
        }
        return nil
    }
}
