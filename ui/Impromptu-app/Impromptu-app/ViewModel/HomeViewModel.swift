//
//  HomeViewModel.swift
//  Impromptu-app
//

import Foundation
import Observation

/// What the status composer is about to publish. It lasts the activity's default length.
struct StatusDraft: Equatable {
    var activity: Activity?
    var note = ""

    static let maxNoteLength = 280

    var trimmedNote: String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum NearbyNotice: Equatable {
    case locationDenied
    /// Works while the app is open, but no background checks or hourly alerts.
    case whileUsingOnly
    case notificationsDenied

    init?(_ outcome: NearbyEnableOutcome) {
        switch outcome.location {
        case .denied, .notDetermined: self = .locationDenied
        case .whileUsing: self = .whileUsingOnly
        case .always:
            guard !outcome.notificationsAllowed else { return nil }
            self = .notificationsDenied
        }
    }
}

/// The feed of everyone's statuses, plus the signed-in user's own status and the
/// composer that edits it. Status changes are mirrored to the widget.
@Observable
final class HomeViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var loadState: LoadState = .idle
    private(set) var myStatus: Status?
    /// Everyone except the signed-in user, in the server's order (active statuses first).
    private(set) var people: [Person] = []
    private(set) var activities: [Activity] = []
    /// The ones picked at sign-up; the composer's drop-down lists these.
    private(set) var savedActivities: [Activity] = []
    private(set) var isUpdatingStatus = false
    /// People within about a mile doing the same activity as you; nil until fetched or when alerts are off.
    private(set) var nearby: NearbyResult?
    private(set) var isNearbyEnabled: Bool
    private(set) var isChangingNearby = false
    /// Why nearby alerts can't fully work, shown under the toggle.
    private(set) var nearbyNotice: NearbyNotice?
    /// Note requests waiting on your reply; the inbox badge.
    private(set) var openNoteRequestCount = 0
    var draft = StatusDraft()
    /// Briefly true after an update goes through.
    private(set) var showsUpdateConfirmation = false
    var errorMessage: String?

    private(set) var user: User
    private let services: Services

    init(user: User, services: Services) {
        self.user = user
        self.services = services
        isNearbyEnabled = services.nearbyAlerts.isEnabled
    }

    var activeMyStatus: Status? {
        myStatus.flatMap { $0.isActive() ? $0 : nil }
    }

    var activePeople: [Person] {
        people.filter { $0.activeStatus != nil }
    }

    var idlePeople: [Person] {
        people.filter { $0.activeStatus == nil }
    }

    /// The drop-down's choices: the saved activities (everything for accounts that never picked any),
    /// plus the drafted one if it came from the full list.
    var myActivities: [Activity] {
        var choices = savedActivities.isEmpty ? activities : savedActivities
        if let selected = draft.activity, !choices.contains(selected) {
            choices.insert(selected, at: 0)
        }
        return choices
    }

    var canPublishDraft: Bool {
        draft.activity != nil && !isUpdatingStatus && draft.note.count <= StatusDraft.maxNoteLength
    }

    // MARK: Loading

    func load() async {
        let isFirstLoad = loadState != .loaded
        if isFirstLoad { loadState = .loading }
        do {
            async let status = services.statuses.currentStatus(for: user.id)
            async let people = services.people.fetchPeople()
            async let activities = services.activities.fetchActivities(for: user.id)
            async let saved = services.activities.fetchSavedActivities(for: user.id)
            let (loadedStatus, loadedPeople, loadedActivities) = try await (status, people, activities)
            myStatus = loadedStatus
            self.people = loadedPeople.filter { $0.id != user.id }
            self.activities = loadedActivities
            // The drop-down falls back to every activity, so the feed still loads without these.
            savedActivities = (try? await saved) ?? savedActivities
            // Later refreshes leave whatever is being typed alone.
            if isFirstLoad { resetDraft() }
            loadState = .loaded
            syncWidget()
            await refreshNearby()
            await refreshNotes()
        } catch {
            // Keep showing what we have if this was a background refresh.
            if loadState == .loaded {
                errorMessage = error.localizedDescription
            } else {
                loadState = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: Status composer

    /// Starts from the current status so "update" means tweak, not retype.
    private func resetDraft() {
        let current = activeMyStatus
        draft = StatusDraft(
            activity: current.flatMap { status in activities.first { $0.id == status.activity.id } },
            note: current?.note ?? ""
        )
    }

    func publishDraft() async {
        guard let activity = draft.activity, canPublishDraft else { return }
        let succeeded = await updateStatus {
            myStatus = try await services.statuses.setStatus(activity: activity, note: draft.trimmedNote, duration: nil, for: user.id)
        }
        if succeeded { showsUpdateConfirmation = true }
    }

    func clearStatus() async {
        guard let myStatus else { return }
        let succeeded = await updateStatus {
            try await services.statuses.clearStatus(myStatus)
            self.myStatus = nil
        }
        if succeeded { draft = StatusDraft() }
    }

    func dismissUpdateConfirmation() {
        showsUpdateConfirmation = false
    }

    private func updateStatus(_ operation: () async throws -> Void) async -> Bool {
        isUpdatingStatus = true
        defer { isUpdatingStatus = false }
        do {
            try await operation()
            syncWidget()
            // A new activity means different matches.
            await refreshNearby()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: Nearby

    func setNearbyAlerts(_ enabled: Bool) async {
        isChangingNearby = true
        defer { isChangingNearby = false }
        if enabled {
            let outcome = await services.nearbyAlerts.enable()
            isNearbyEnabled = outcome.isEnabled
            nearbyNotice = NearbyNotice(outcome)
            await refreshNearby()
        } else {
            await services.nearbyAlerts.disable(userId: user.id)
            isNearbyEnabled = false
            nearbyNotice = nil
            nearby = nil
        }
    }

    /// Fetching marks the people shown as seen, so they won't trigger a notification later.
    func refreshNearby() async {
        guard isNearbyEnabled else { return }
        // Permissions can change in Settings while the app is away.
        switch services.nearbyAlerts.locationAuthorization {
        case .denied, .notDetermined: nearbyNotice = .locationDenied
        case .whileUsing: nearbyNotice = .whileUsingOnly
        case .always where nearbyNotice != .notificationsDenied: nearbyNotice = nil
        case .always: break
        }
        // Nearby is an extra; if it fails, the rest of the feed still works.
        nearby = try? await services.nearbyAlerts.refreshInForeground()
    }

    // MARK: Notes

    /// Polls the inbox; new requests and replies show as banners while the app is open.
    func refreshNotes() async {
        guard let inbox = try? await services.noteMonitor.poll(notify: true) else { return }
        openNoteRequestCount = inbox.openIncomingCount
    }

    // MARK: Custom activities

    /// Returns the new activity, or nil if the server rejected it (e.g. duplicate name).
    func createActivity(name: String, durationMinutes: Int) async -> Activity? {
        do {
            let activity = try await services.activities.createActivity(name: name, durationMinutes: durationMinutes, for: user.id)
            // Match the server's order: custom activities first.
            activities.insert(activity, at: 0)
            return activity
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func deleteActivity(_ activity: Activity) async {
        guard activity.isCustom else { return }
        do {
            try await services.activities.deleteActivity(activity, for: user.id)
            activities.removeAll { $0.id == activity.id }
            savedActivities.removeAll { $0.id == activity.id }
            if draft.activity == activity { draft.activity = nil }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Profile and appearance

    /// The name was changed in Settings.
    func userDidChange(_ user: User) {
        guard user != self.user else { return }
        self.user = user
        syncWidget()
    }

    /// Light/dark was toggled; the widget follows the app.
    func appearanceDidChange() {
        services.widgets.reloadAppearance()
    }

    private func syncWidget() {
        services.widgets.sync(user: user, myStatus: myStatus, people: people)
    }
}
