import Vapor
import Twilio

struct BasicZorkController {
    fileprivate func incomingMessage(req: Request, sms: IncomingSMS) throws -> ResponseEncodable {
        
    }
}

extension BasicZorkController: RouteCollection {
    func boot(router: Router) throws {
        router.post(IncomingSMS.self, at: "incoming", use: self.incomingMessage)
    }
}
