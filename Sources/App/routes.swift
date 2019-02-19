import Vapor
import Twilio

import Foundation

/// Register your application's routes here.
public func routes(_ router: Router) throws {
    // Basic "It works" example
    router.get { req in
        return "It works!"
    }
    
    // Basic "Hello, world!" example
    router.get("hello") { req -> String in
        return "Hello, world!"
    }
    
    try BasicZorkController().boot(router: router)
    
    router.post("incoming") { (req) -> Future<Response> in
        // This object will give you access to all of the properties of incoming texts
        let sms = try req.content.syncDecode(IncomingSMS.self)
        print(sms)
        
        return ZorkHelper.send(command: sms.body, phoneNumber: sms.from, on: req).flatMap { output in
            let twilio  = try req.make(Twilio.self)
            
            return try twilio.longResponse(incomingSMS: sms, outgoingMessages: output, on: req)
        }
    }
}
