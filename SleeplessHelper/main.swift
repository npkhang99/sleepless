//
//  main.swift
//  SleeplessHelper
//

import Foundation

final class HelperTool: NSObject, NSXPCListenerDelegate, SleeplessHelperProtocol {
    private let listener: NSXPCListener

    override init() {
        listener = NSXPCListener(machServiceName: SleeplessHelperConstants.machServiceName)
        super.init()
        listener.delegate = self
    }

    func run() {
        listener.resume()
        RunLoop.current.run()
    }

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: SleeplessHelperProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    func setSleepDisabled(_ disabled: Bool, reply: @escaping (NSError?) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-a", "disablesleep", disabled ? "1" : "0"]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            reply(error as NSError)
            return
        }

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "pmset failed"
            reply(NSError(
                domain: SleeplessHelperConstants.machServiceName,
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: message]
            ))
            return
        }

        reply(nil)
    }
}

HelperTool().run()
