//
//  SleeplessHelperProtocol.swift
//  sleepless
//

import Foundation

@objc protocol SleeplessHelperProtocol {
    func setSleepDisabled(_ disabled: Bool, reply: @escaping (NSError?) -> Void)
}

enum SleeplessHelperConstants {
    static let machServiceName = "com.curoa99.sleepless.helper.v2"
}
