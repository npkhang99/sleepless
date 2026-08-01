//
//  AppDelegate.swift
//  sleepless
//

import AppKit
import ServiceManagement
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
    private var statusItem: NSStatusItem!
    private var isRelaunchingForUpdate = false
    private let sleepManager = SleepManager()
    private let helper = HelperManager.shared
    private let loginItem = SMAppService.mainApp
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = updaterController
        helper.registerIfNeeded()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateIcon()

        if let button = statusItem.button {
            button.action = #selector(statusBarClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if isRelaunchingForUpdate {
            return .terminateNow
        }

        switch sleepManager.mode {
        case .off:
            return .terminateNow
        case .lidOpen:
            sleepManager.setMode(.off) { _ in }
            return .terminateNow
        case .lidClosed:
            break
        }

        sleepManager.setMode(.off) { result in
            switch result {
            case .success:
                NSApp.reply(toApplicationShouldTerminate: true)
            case .failure(let error):
                self.presentError(error)
                NSApp.reply(toApplicationShouldTerminate: false)
            }
        }
        return .terminateLater
    }

    @objc private func statusBarClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showMenu()
        } else {
            cycleMode()
        }
    }

    private func cycleMode() {
        guard !sleepManager.isChanging else { return }

        sleepManager.cycle { result in
            self.updateIcon()
            if case .failure(let error) = result {
                self.presentError(error)
            }
        }
    }

    private func showMenu() {
        let menu = NSMenu()

        let statusTitle = sleepManager.isChanging ? "Status: Changing…" : statusText
        let statusItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        menu.addItem(.separator())

        menu.addItem(modeMenuItem(title: "Off — Allow Sleep", mode: .off, action: #selector(selectOffMode)))
        menu.addItem(modeMenuItem(
            title: "Keep Awake — Lid Open",
            mode: .lidOpen,
            action: #selector(selectLidOpenMode)
        ))
        menu.addItem(modeMenuItem(
            title: "Keep Awake — Lid Closed",
            mode: .lidClosed,
            action: #selector(selectLidClosedMode)
        ))

        if sleepManager.mode == .lidClosed {
            let monitorItem = NSMenuItem(
                title: "Keep Monitor On",
                action: #selector(toggleLidClosedMonitor),
                keyEquivalent: ""
            )
            monitorItem.target = self
            monitorItem.indentationLevel = 1
            monitorItem.state = sleepManager.keepsMonitorOnInLidClosedMode ? .on : .off
            monitorItem.isEnabled = !sleepManager.isChanging
            menu.addItem(monitorItem)
        }

        if helper.state != .enabled {
            menu.addItem(.separator())
            let helperItem = NSMenuItem(
                title: "Approve Lid Closed Helper…",
                action: #selector(openHelperApproval),
                keyEquivalent: ""
            )
            helperItem.target = self
            menu.addItem(helperItem)
        }

        menu.addItem(.separator())

        let launchAtLoginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLoginItem.target = self
        launchAtLoginItem.state = loginItem.status == .enabled ? .on : .off
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())

        let updateItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        updateItem.target = self
        updateItem.isEnabled = updaterController.updater.canCheckForUpdates
        menu.addItem(updateItem)

        let automaticUpdateItem = NSMenuItem(
            title: "Automatically Install Updates",
            action: #selector(toggleAutomaticUpdates),
            keyEquivalent: ""
        )
        automaticUpdateItem.target = self
        automaticUpdateItem.state = updaterController.updater.automaticallyDownloadsUpdates
            ? .on
            : .off
        automaticUpdateItem.isEnabled = updaterController.updater.allowsAutomaticUpdates
        menu.addItem(automaticUpdateItem)

        menu.addItem(.separator())

        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "Unknown"
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "Unknown"
        let versionItem = NSMenuItem(
            title: "Version \(version) (\(build))",
            action: nil,
            keyEquivalent: ""
        )
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        let quitItem = NSMenuItem(title: "Quit Sleepless", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        self.statusItem.menu = menu
        self.statusItem.button?.performClick(nil)
        // Remove the menu so left-click isn't hijacked next time
        self.statusItem.menu = nil
    }

    private var statusText: String {
        switch sleepManager.mode {
        case .off:
            return "Status: Sleep allowed"
        case .lidOpen:
            return "Status: Awake while lid is open"
        case .lidClosed:
            return sleepManager.keepsMonitorOnInLidClosedMode
                ? "Status: Awake with lid closed, monitor on"
                : "Status: Awake even with lid closed"
        }
    }

    private func modeMenuItem(title: String, mode: SleepMode, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = sleepManager.mode == mode ? .on : .off
        item.isEnabled = !sleepManager.isChanging
        return item
    }

    @objc private func selectOffMode() {
        setMode(.off)
    }

    @objc private func selectLidOpenMode() {
        setMode(.lidOpen)
    }

    @objc private func selectLidClosedMode() {
        setMode(.lidClosed)
    }

    @objc private func toggleLidClosedMonitor() {
        let result = sleepManager.toggleMonitorInLidClosedMode()
        updateIcon()
        if case .failure(let error) = result {
            presentError(error)
        }
    }

    @objc private func openHelperApproval() {
        helper.registerIfNeeded()
        helper.openApprovalSettings()
    }

    @objc private func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    @objc private func toggleAutomaticUpdates() {
        updaterController.updater.automaticallyDownloadsUpdates.toggle()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            switch loginItem.status {
            case .enabled:
                try loginItem.unregister()
            case .notRegistered:
                try loginItem.register()
            case .requiresApproval:
                SMAppService.openSystemSettingsLoginItems()
            case .notFound:
                throw LoginItemError.unavailable
            @unknown default:
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch {
            presentError(error, message: "Sleepless couldn’t change the login setting.")
        }
    }

    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        DispatchQueue.main.async(execute: immediateInstallHandler)
        return true
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        isRelaunchingForUpdate = true
    }

    private func setMode(_ mode: SleepMode) {
        guard !sleepManager.isChanging else { return }
        sleepManager.setMode(mode) { result in
            self.updateIcon()
            if case .failure(let error) = result {
                self.presentError(error)
            }
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func updateIcon() {
        let symbolName: String
        let toolTip: String
        switch sleepManager.mode {
        case .off:
            symbolName = "cup.and.saucer"
            toolTip = "Sleepless is off"
        case .lidOpen:
            symbolName = "cup.and.saucer.fill"
            toolTip = "Sleepless is keeping the Mac awake while the lid is open"
        case .lidClosed:
            symbolName = "laptopcomputer"
            toolTip = sleepManager.keepsMonitorOnInLidClosedMode
                ? "Sleepless is keeping the Mac and monitor awake with the lid closed"
                : "Sleepless is keeping the Mac awake even with the lid closed"
        }
        statusItem.button?.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Sleepless")
        statusItem.button?.toolTip = toolTip
    }

    private func presentError(
        _ error: Error,
        message: String = "Sleepless couldn’t change sleep behavior."
    ) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning

        if case .approvalRequired = error as? HelperError {
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                helper.openApprovalSettings()
            }
        } else {
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}

private enum LoginItemError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "The app’s login item is unavailable. Move Sleepless to Applications and try again."
    }
}
