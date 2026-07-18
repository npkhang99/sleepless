//
//  SleepManager.swift
//  sleepless
//

import Foundation
import IOKit.pwr_mgt

enum SleepMode: Int {
    case off
    case lidOpen
    case lidClosed

    var isAwake: Bool { self != .off }
}

enum SleepManagerError: LocalizedError {
    case assertionFailed(IOReturn)

    var errorDescription: String? {
        switch self {
        case .assertionFailed(let code):
            return "The temporary sleep-prevention assertion could not be created (IOKit error \(code))."
        }
    }
}

@Observable
final class SleepManager {
    private(set) var mode: SleepMode
    private(set) var isChanging = false
    private var assertionID: IOPMAssertionID = 0
    private let helper = HelperManager.shared

    var isAwake: Bool { mode.isAwake }

    init() {
        mode = Self.isSystemSleepDisabled() ? .lidClosed : .off
    }

    func toggle(completion: @escaping (Result<Void, Error>) -> Void) {
        setMode(mode == .off ? .lidOpen : .off, completion: completion)
    }

    func setMode(_ newMode: SleepMode, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !isChanging, newMode != mode else {
            completion(.success(()))
            return
        }

        if mode == .lidClosed || newMode == .lidClosed {
            changeClamshellSetting(enabled: newMode == .lidClosed) { result in
                switch result {
                case .success:
                    completion(self.applyLocalMode(newMode))
                case .failure:
                    completion(result)
                }
            }
            return
        }

        completion(applyLocalMode(newMode))
    }

    private func applyLocalMode(_ newMode: SleepMode) -> Result<Void, Error> {
        releaseAssertion()

        if newMode == .lidOpen {
            let reason = "Sleepless: Keeping Mac awake while the lid is open" as CFString
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypeNoDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason,
                &assertionID
            )
            guard result == kIOReturnSuccess else {
                assertionID = 0
                mode = .off
                return .failure(SleepManagerError.assertionFailed(result))
            }
        }

        mode = newMode
        return .success(())
    }

    private func releaseAssertion() {
        guard assertionID != 0 else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
    }

    private func changeClamshellSetting(
        enabled: Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        isChanging = true
        Task {
            do {
                try await helper.setSleepDisabled(enabled)
                isChanging = false
                completion(.success(()))
            } catch {
                isChanging = false
                completion(.failure(error))
            }
        }
    }

    private static func isSystemSleepDisabled() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return output.range(
            of: #"SleepDisabled\s+1"#,
            options: .regularExpression
        ) != nil
    }
}
