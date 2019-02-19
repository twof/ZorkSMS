import Vapor
import Twilio
import Files

struct BasicZorkController {
    fileprivate func incomingMessage(req: Request, sms: IncomingSMS) throws -> Future<Response> {
        return try run(command: sms.body, phoneNumber: sms.from, on: req).map { output in
            let twilio  = try req.make(Twilio.self)
            
            let response = SMSResponse(output.map { Message(body: $0) })
            
            return try twilio.respond(with: response, on: req)
        }
    }
    
    fileprivate func run(command: String, phoneNumber: String, on req: Request) throws -> Future<[String]> {
        // going to succeed this promise with a list of sms bodies
        let promise = req.eventLoop.newPromise([String].self)
        
        // state
        var isNewGame = false
        
        // If the game directory hasn't been created yet
        if !Folder.current.containsSubfolder(named: "saveFiles") {
            // create the game directory
            try Folder.current.createSubfolder(named: "saveFiles")
        }
        
        let saveFolder = try Folder.current.subfolder(named: "saveFiles")
        
        // if the directory associated with this phone number hasn't been created yet
        if !saveFolder.containsSubfolder(named: phoneNumber) {
            // create the save directory
            try! saveFolder.createSubfolder(named: phoneNumber)
            // this is a new game, so we're going to note that
            isNewGame = true
        }
        
        let currentSaveFolder = try saveFolder.subfolder(named: phoneNumber)
        
        // Set up a zork process, and direct it to run in the directory associated with the current phone number
        let task = Process()
        task.currentDirectoryPath = currentSaveFolder.path
        task.executableURL = URL(fileURLWithPath: "/usr/local/bin/zork")
        
        // Set up a pipe to capture output from stdout and stderr
        let outPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = outPipe
        
        let inPipe = Pipe()
        task.standardInput = inPipe
        
        // start running the task
        // this will put us into the interactive zork game
        try task.run()
        
        // if this isn't a new game, we need to restore from save
        // and execute the first command
        // we only want to send back the game intro upon the first text
        if !isNewGame {
            let restore = "restore\n".data(using: .utf8)
            inPipe.fileHandleForWriting.write(restore!)
            
            let command = "\(command)\n".data(using: .utf8)
            inPipe.fileHandleForWriting.write(command!)
        }
        
        let save = "save\n".data(using: .utf8)
        inPipe.fileHandleForWriting.write(save!)
        
        let quit = "quit\n".data(using: .utf8)
        inPipe.fileHandleForWriting.write(quit!)
        
        let confirm = "yes\n".data(using: .utf8)
        inPipe.fileHandleForWriting.write(confirm!)
        
        // after saving and quiting, the process will exit
        task.waitUntilExit()
        
        // Capture all output from zork
        let zorkOutputData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let zorkOutputString = String(data: zorkOutputData, encoding: String.Encoding.utf8)!
        
        // if this is a new game, we just want the first part of output
        // That'll be the intro to the game
        // otherwise
        // We're going to want the third bit of output
        // That will be the result of the submitted command
        let indices =  (isNewGame) ? [0] : [2]
        
        // putting zork output through a processing pipeline
        
        // Can't split on more than one character, so we're going to start by replacing the substring we want to split on with a character that will never show up in output
        let replaced = zorkOutputString.replacingOccurrences(of: "\n>", with: "‽")
        let split = zorkOutputString.split(separator: "‽")
        let enumerated = split.enumerated()
        let filtered = enumerated.filter { indices.contains($0.offset) }
        let stringified = filtered.map { String($0.element) }
        let output = stringified
        
        promise.succeed(result: output)
        
        return promise.futureResult
    }
}

extension BasicZorkController: RouteCollection {
    func boot(router: Router) throws {
        router.post(IncomingSMS.self, at: "incoming", use: self.incomingMessage)
    }
}
