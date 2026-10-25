//
//  StatusPreferencesStore.swift
//  Impromptu-app
//

import Foundation

/// How the user wants their status kept up to date. The API doesn't store this, so it's saved
/// on this device, per user.
protocol StatusPreferencesStoring {
    /// Manual only until the user chooses.
    func sources(for userId: UUID) -> Set<StatusSource>
    func save(_ sources: Set<StatusSource>, for userId: UUID)
}

final class StatusPreferencesStore: StatusPreferencesStoring {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func sources(for userId: UUID) -> Set<StatusSource> {
        guard let raw = defaults.stringArray(forKey: key(for: userId)) else { return [.manual] }
        return Set(raw.compactMap(StatusSource.init(rawValue:)))
    }

    func save(_ sources: Set<StatusSource>, for userId: UUID) {
        defaults.set(sources.map(\.rawValue).sorted(), forKey: key(for: userId))
    }

    private func key(for userId: UUID) -> String {
        "statusSources.\(userId.uuidString)"
    }
}
