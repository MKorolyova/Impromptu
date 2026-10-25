//
//  BackgroundRefresh.swift
//  Impromptu-app
//

import BackgroundTasks
import Foundation

/// The hourly background refresh (nearby check and note polling).
///
/// Registered with BGTaskScheduler directly rather than SwiftUI's `.backgroundTask` modifier:
/// SwiftUI registers late, when the scene is built, and submitting a request before a handler
/// exists raises an Objective-C exception that `try?` can't catch.
enum BackgroundRefresh {
    /// Must match BGTaskSchedulerPermittedIdentifiers in Config/App-Info.plist.
    static let taskIdentifier = "xhilgerz.Impromptu-app.nearby-check"

    /// Requests may only be submitted once this is true.
    private(set) static var isRegistered = false

    /// Call from `App.init`, before anything submits a request; iOS requires it before launch finishes.
    static func register(_ work: @escaping @MainActor () async -> Void) {
        guard !isRegistered else { return }
        isRegistered = BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: .main) { task in
            MainActor.assumeIsolated {
                let run = Task {
                    await work()
                    task.setTaskCompleted(success: !Task.isCancelled)
                }
                // iOS is about to suspend the app; stop and report it unfinished.
                task.expirationHandler = { run.cancel() }
            }
        }
    }
}
