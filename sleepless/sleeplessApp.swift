//
//  sleeplessApp.swift
//  sleepless
//

import SwiftUI

@main
struct sleeplessApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        if NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier!).count > 1 {
            NSApp.terminate(nil)
        }
    }

    var body: some Scene {
        Settings { EmptyView() }
    }
}
