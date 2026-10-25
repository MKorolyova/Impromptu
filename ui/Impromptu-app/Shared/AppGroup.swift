//
//  AppGroup.swift
//  Impromptu-app
//
//  Compiled into both the app and the widget extension.
//

import Foundation

nonisolated enum AppGroup {
    /// Must match the App Groups entitlement on the app and widget targets.
    static let identifier = "group.xhilgerz.Impromptu-app"

    /// Shared container both processes can read and write.
    /// Falls back to the process's own Application Support directory when the
    /// entitlement is missing (e.g. unsigned builds) so the app still works;
    /// the widget just won't see the data in that case.
    static var containerURL: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
            ?? URL.applicationSupportDirectory
    }
}
