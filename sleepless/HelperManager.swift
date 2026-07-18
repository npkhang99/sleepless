//
//  HelperManager.swift
//  sleepless
//

import AppKit
import Foundation
import ServiceManagement

enum HelperState: Equatable {
    case notRegistered
    case awaitingApproval
    case enabled
    case notFound
}

enum HelperError: LocalizedError {
    case approvalRequired
    case helperUnavailable
    case connectionFailed(String)
    case remoteError(Error)

    var errorDescription: String? {
        switch self {
        case .approvalRequired:
            return "Approve the Sleepless background helper once in System Settings, then select Lid Closed mode again."
        case .helperUnavailable:
            return "The Sleepless background helper is unavailable."
        case .connectionFailed(let detail):
            return "Couldn’t connect to the Sleepless helper: \(detail)"
        case .remoteError(let error):
            return error.localizedDescription
        }
    }
}

final class HelperManager {
    static let shared = HelperManager()

    private static let plistName = "com.curoa99.sleepless.helper.v2.plist"

    private let service = SMAppService.daemon(plistName: plistName)
    private var connection: NSXPCConnection?

    private init() {}

    var state: HelperState {
        switch service.status {
        case .notRegistered:
            return .notRegistered
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .awaitingApproval
        case .notFound:
            return .notFound
        @unknown default:
            return .notFound
        }
    }

    var isUsable: Bool { state == .enabled }

    func registerIfNeeded() {
        guard state != .enabled, state != .awaitingApproval else { return }
        do {
            try service.register()
        } catch {
            NSLog("Sleepless: helper registration failed: \((error as NSError).localizedDescription)")
        }
    }

    func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func setSleepDisabled(_ disabled: Bool) async throws {
        registerIfNeeded()

        switch state {
        case .enabled:
            break
        case .awaitingApproval:
            throw HelperError.approvalRequired
        case .notRegistered, .notFound:
            throw HelperError.helperUnavailable
        }

        let proxy = try remoteProxy()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            proxy.setSleepDisabled(disabled) { error in
                if let error {
                    continuation.resume(throwing: HelperError.remoteError(error))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func remoteProxy() throws -> SleeplessHelperProtocol {
        let connection = connection ?? makeConnection()
        self.connection = connection

        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ [weak self] error in
            DispatchQueue.main.async {
                self?.connection?.invalidate()
                self?.connection = nil
            }
            NSLog("Sleepless: helper connection failed: \(error.localizedDescription)")
        }) as? SleeplessHelperProtocol else {
            throw HelperError.connectionFailed("The XPC proxy has an unexpected type.")
        }
        return proxy
    }

    private func makeConnection() -> NSXPCConnection {
        let connection = NSXPCConnection(
            machServiceName: SleeplessHelperConstants.machServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: SleeplessHelperProtocol.self)
        connection.invalidationHandler = { [weak self] in
            DispatchQueue.main.async { self?.connection = nil }
        }
        connection.interruptionHandler = { [weak self] in
            DispatchQueue.main.async { self?.connection = nil }
        }
        connection.resume()
        return connection
    }
}
