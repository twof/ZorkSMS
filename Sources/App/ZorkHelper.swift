import Foundation
import Vapor
import Files

// Going to do something with chain of command I think

struct GameState {
    var isNewGame: Bool = false
    var messages: [String] = []
    var task: Process = Process()
    var outPipe: Pipe = Pipe()
    var inPipe: Pipe = Pipe()
    var accumulator: String = ""
    var command: String? = nil
}

protocol ZorkCheck {
    func stateCheck(state: GameState) -> Bool
    func performAction(state: GameState) -> GameState
    func reduce(state: GameState) -> GameState
}

extension ZorkCheck {
    func stateCheck(state: GameState) -> Bool {
        return true
    }
    
    func reduce(state: GameState) -> GameState {
        if self.stateCheck(state: state) {
            return self.performAction(state: state)
        }
        return state
    }
}

public struct ZorkHelper {
    class SetupEnvironment: ZorkCheck {
        func stateCheck(state: GameState) -> Bool {
            return !Folder.current.containsSubfolder(named: "saveFiles")
        }
        
        func performAction(state: GameState) -> GameState {
            do {
                try Folder.current.createSubfolder(named: "saveFiles")
            } catch {
                fatalError()
            }
            
            return state
        }
    }
    
    class SetupNewGame: ZorkCheck {
        let phoneNumber: String
        
        init(phoneNumber: String) {
            self.phoneNumber = phoneNumber
        }
        
        func stateCheck(state: GameState) -> Bool {
            guard let saveFolder = try? Folder.current.subfolder(named: "saveFiles") else { fatalError() }
            
            return !saveFolder.containsSubfolder(named: phoneNumber)
        }
        
        func performAction(state: GameState) -> GameState {
            guard let saveFolder = try? Folder.current.subfolder(named: "saveFiles") else { fatalError() }
            
            try! saveFolder.createSubfolder(named: phoneNumber)
            
            var temp = state
            
            temp.isNewGame = true
            temp.messages.append("If you want to know the available commands, use \"HLP\"")
            
            return temp
        }
    }
    
    class CreateTask: ZorkCheck {
        let phoneNumber: String
        
        init(phoneNumber: String) {
            self.phoneNumber = phoneNumber
        }
        
        func performAction(state: GameState) -> GameState {
            guard
                let saveFolder = try? Folder.current.subfolder(named: "saveFiles"),
                let currentSaveFolder = try? saveFolder.subfolder(named: phoneNumber)
                else { fatalError() }
            
            let task = Process()
            task.currentDirectoryPath = currentSaveFolder.path
            task.executableURL = URL(fileURLWithPath: "/usr/local/bin/zork")
            
            var temp = state
            temp.task = task
            return temp
        }
    }
    
    class CreatePipes: ZorkCheck {
        func performAction(state: GameState) -> GameState {
            let outPipe = Pipe()
            
            var temp = state
            
            state.task.standardOutput = outPipe
            state.task.standardError = outPipe
            
            let inPipe = Pipe()
            state.task.standardInput = inPipe
            
            temp.outPipe = outPipe
            temp.inPipe = inPipe
            return temp
        }
    }
    
    class RunTask: ZorkCheck {
        func performAction(state: GameState) -> GameState {
            try! state.task.run()
            return state
        }
    }
    
    // Twilio blocks the phrase help and sends back instructions to unsubscribe, so we have to offer
    // a slightly altered command
    class RepairAlteredHelpCommand: ZorkCheck {
        let command: String
        
        init(command: String) {
            self.command = command
        }
        
        func stateCheck(state: GameState) -> Bool {
            return self.command.lowercased() == "hlp"
        }
        
        func performAction(state: GameState) -> GameState {
            var temp = state
            temp.command = "help"
            return temp
        }
    }
    
    class RunNewGameMainCommands: ZorkCheck {
        func stateCheck(state: GameState) -> Bool {
            return state.isNewGame
        }
        
        func performAction(state: GameState) -> GameState {
            mainCommands(command: nil, inPipe: state.inPipe)
            return state
        }
    }
    
    class RunExistingGameMainCommands: ZorkCheck {
        let command: String
        
        init(command: String) {
            self.command = command
        }
        
        func stateCheck(state: GameState) -> Bool {
            return !state.isNewGame
        }
        
        func performAction(state: GameState) -> GameState {
            mainCommands(command: state.command ?? self.command, inPipe: state.inPipe)
            return state
        }
    }
    
    class WaitUntilExit: ZorkCheck {
        func performAction(state: GameState) -> GameState {
            state.task.waitUntilExit()
            return state
        }
    }
    
    public static func send(command: String, phoneNumber: String, on req: Request) -> Future<[String]> {
        let promise = req.eventLoop.newPromise([String].self)
        
        let setupEnvironment = SetupEnvironment()
        let setupNewGame = SetupNewGame(phoneNumber: phoneNumber)
        let createTask = CreateTask(phoneNumber: phoneNumber)
        let createPipes = CreatePipes()
        let runTask = RunTask()
        let repairHelpCommand = RepairAlteredHelpCommand(command: command)
        let runNewGameCommands = RunNewGameMainCommands()
        let runExistingGameCommands = RunExistingGameMainCommands(command: command)
        let waitUntilExit = WaitUntilExit()
        
        let reducers: [ZorkCheck] = [
            setupEnvironment,
            setupNewGame,
            createTask,
            createPipes,
            runTask,
            repairHelpCommand,
            runNewGameCommands,
            runExistingGameCommands,
            waitUntilExit
        ]
        
        let finalState = reducers.reduce(GameState()) { (gameState, reducer) -> GameState in
            return reducer.reduce(state: gameState)
        }
        
        let data = finalState.outPipe.fileHandleForReading.readDataToEndOfFile()
        let str = String(data: data, encoding: String.Encoding.utf8)!
        
        let indices = [2] + ((finalState.isNewGame) ? [0] : [])
        let replaced = str.replacingOccurrences(of: "\n>", with: "‽")
        let split = replaced.split(separator: "‽")
        let enumerated = split.enumerated()
        let filtered = enumerated.filter { indices.contains($0.offset) }
        let stringified = filtered.map { String($0.element) }
        let output = stringified
        
        let result: [String] = output + finalState.messages
        
        let processedResult = result.map { message -> [String] in
            if message.count > 1000 {
                
                // There's a character limit on twilio messages
                let preprocessed: String = message.enumerated().map { (offset, element) in
                    let altered: String = ((offset + 1) % 1000 == 0) ? "🔤" + String(element) : String(element)
                    return altered
                }.joined()
                
                let messages = preprocessed.split(separator: "🔤")
                return messages.map { String($0) }
            }
            return [message]
        }.flatMap { $0 }

        promise.succeed(result: processedResult)
        
        return promise.futureResult
    }
    
    fileprivate static func mainCommands(command: String?, inPipe: Pipe) {
        let restore = "restore\n".data(using: .utf8)
        inPipe.fileHandleForWriting.write(restore!)
        
        if let command = command {
            let command = "\(command)\n".data(using: .utf8)
            inPipe.fileHandleForWriting.write(command!)
        }
        
        let save = "save\n".data(using: .utf8)
        inPipe.fileHandleForWriting.write(save!)
        
        let quit = "quit\n".data(using: .utf8)
        inPipe.fileHandleForWriting.write(quit!)
        
        let confirm = "yes\n".data(using: .utf8)
        inPipe.fileHandleForWriting.write(confirm!)
    }
}
