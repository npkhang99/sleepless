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

    var next: SleepMode {
        switch self {
        case .off: return .lidOpen
        case .lidOpen: return .lidClosed
        case .lidClosed: return .off
        }
    }
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
    private(set) var keepsMonitorOnInLidClosedMode: Bool
    private(set) var isChanging = false
    private var assertionID: IOPMAssertionID = 0
    private let helper = HelperManager.shared
    private static let keepsMonitorOnKey = "keepsMonitorOnInLidClosedMode"

    var isAwake: Bool { mode.isAwake }

    init() {
        mode = Self.isSystemSleepDisabled() ? .lidClosed : .off
        let defaults = UserDefaults.standard
        keepsMonitorOnInLidClosedMode = defaults.object(
            forKey: Self.keepsMonitorOnKey
        ) as? Bool ?? true

        if mode == .lidClosed, keepsMonitorOnInLidClosedMode {
            _ = createDisplayAssertion(reason: "Sleepless: Keeping monitor on in Lid Closed mode")
        }
    }

    func cycle(completion: @escaping (Result<Void, Error>) -> Void) {
        setMode(mode.next, completion: completion)
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

    func toggleMonitorInLidClosedMode() -> Result<Void, Error> {
        guard mode == .lidClosed else { return .success(()) }

        if keepsMonitorOnInLidClosedMode {
            releaseAssertion()
            keepsMonitorOnInLidClosedMode = false
        } else {
            let result = createDisplayAssertion(
                reason: "Sleepless: Keeping monitor on in Lid Closed mode"
            )
            guard case .success = result else { return result }
            keepsMonitorOnInLidClosedMode = true
        }

        UserDefaults.standard.set(
            keepsMonitorOnInLidClosedMode,
            forKey: Self.keepsMonitorOnKey
        )
        return .success(())
    }

    private func applyLocalMode(_ newMode: SleepMode) -> Result<Void, Error> {
        releaseAssertion()

        if newMode == .lidOpen {
            let result = createDisplayAssertion(
                type: kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                reason: "Sleepless: Keeping Mac awake while the lid is open"
            )
            guard case .success = result else {
                mode = .off
                return result
            }
        } else if newMode == .lidClosed, keepsMonitorOnInLidClosedMode {
            let result = createDisplayAssertion(
                reason: "Sleepless: Keeping monitor on in Lid Closed mode"
            )
            guard case .success = result else {
                mode = .lidClosed
                return result
            }
        }

        mode = newMode
        return .success(())
    }

    private func createDisplayAssertion(
        type: CFString = kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
        reason: String
    ) -> Result<Void, Error> {
        let result = IOPMAssertionCreateWithName(
            type,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertionID
        )
        guard result == kIOReturnSuccess else {
            assertionID = 0
            return .failure(SleepManagerError.assertionFailed(result))
        }
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
