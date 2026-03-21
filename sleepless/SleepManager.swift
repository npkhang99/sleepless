//
//  SleepManager.swift
//  sleepless
//

import Foundation
import IOKit.pwr_mgt

@Observable
final class SleepManager {
    private(set) var isAwake = false
    private var assertionID: IOPMAssertionID = 0

    func toggle() {
        if isAwake {
            disableAssertion()
        } else {
            enableAssertion()
        }
    }

    private func enableAssertion() {
        let reason = "Sleepless: Keeping Mac awake" as CFString
        let success = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &assertionID
        )
        if success == kIOReturnSuccess {
            isAwake = true
        }
    }

    private func disableAssertion() {
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        isAwake = false
    }
}
