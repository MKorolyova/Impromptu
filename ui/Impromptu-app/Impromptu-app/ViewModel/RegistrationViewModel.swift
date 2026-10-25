//
//  RegistrationViewModel.swift
//  Impromptu-app
//

import Foundation
import Observation

/// The sign-up sheet. Nothing is saved until the account is needed (connecting Google Calendar, or the
/// last step), so until then every step can be revisited and changed. The session only switches to the
/// home screen after the last step.
@Observable
final class RegistrationViewModel {
    enum Step: Int, CaseIterable, Comparable {
        case credentials
        case profile
        case activities
        case calendar
        case statusSources

        static func < (lhs: Step, rhs: Step) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    enum CalendarState: Equatable {
        case notConnected
        case connecting
        case connected
        case failed(String)
    }

    static let minimumPasswordLength = 8
    static let requiredActivityCount = 5
    static let maxActivityNameLength = 50
    static let maxNicknameLength = 50
    /// In everyone's list without being picked. Not standard activities, so each user gets their own.
    static let defaultActivities: [(name: String, durationMinutes: Int)] = [("Do not disturb", 60), ("Free", 60)]
    static let defaultActivityNames = defaultActivities.map { $0.name }
    /// Default length for activities typed in during sign-up.
    static let customActivityMinutes = 60

    private(set) var step: Step = .credentials
    /// Which way the last step change went, for the slide direction.
    private(set) var isMovingBack = false

    var email = ""
    var password = ""
    var firstName = ""
    var lastName = ""
    var nickname = ""

    var query = ""
    /// Everything the user can pick: the ones they typed in on top, then the standard ones (the
    /// built-in list from `GET /activities`).
    private(set) var activities: [ActivityChoice] = []
    /// Picked activities, in the order they were picked. Excludes the defaults.
    private(set) var selectedIds: [ActivityChoice.ID] = []
    private(set) var activitiesLoadError: String?
    /// The list has come back, even if it was empty.
    private(set) var hasLoadedActivities = false

    private(set) var calendarState: CalendarState = .notConnected
    var statusSources: Set<StatusSource> = [.manual]

    private(set) var isWorking = false
    private(set) var errorMessage: String?
    /// Set once the account exists. After that its email and password can't be changed here.
    private(set) var user: User?
    /// Rows made for the defaults, so trying again doesn't make them twice.
    private var defaultActivityIds: [String: UUID] = [:]

    private let services: Services

    init(services: Services) {
        self.services = services
    }

    // MARK: Navigation

    var isAccountCreated: Bool {
        user != nil
    }

    var canGoBack: Bool {
        step != .credentials && !isWorking
    }

    var canContinue: Bool {
        guard !isWorking else { return false }
        switch step {
        case .credentials:
            return isAccountCreated
                || (trimmed(email).contains("@") && password.count >= Self.minimumPasswordLength)
        case .profile:
            return !trimmed(firstName).isEmpty && !trimmed(lastName).isEmpty
                && trimmed(nickname).count <= Self.maxNicknameLength
        case .activities:
            return selectedIds.count >= Self.requiredActivityCount
        case .calendar:
            return calendarState != .connecting
        case .statusSources:
            return !statusSources.isEmpty
        }
    }

    func goBack() {
        guard canGoBack, let previous = Step(rawValue: step.rawValue - 1) else { return }
        errorMessage = nil
        move(to: previous)
    }

    /// Moves to the next step. The last step saves everything and signs in.
    func advance(session: SessionViewModel) async {
        guard canContinue else { return }
        errorMessage = nil
        switch step {
        case .credentials:
            if isAccountCreated {
                move(to: .profile)
            } else {
                await checkEmail()
            }
        case .profile:
            move(to: .activities)
            if !hasLoadedActivities { await loadActivities() }
        case .activities:
            move(to: .calendar)
        case .calendar:
            move(to: .statusSources)
        case .statusSources:
            await finish(session: session)
        }
    }

    private func move(to newStep: Step) {
        isMovingBack = newStep < step
        step = newStep
    }

    // MARK: Account

    /// The name friends will see, as typed so far.
    var previewName: String {
        let nickname = trimmed(nickname)
        return nickname.isEmpty ? "\(trimmed(firstName)) \(trimmed(lastName))" : nickname
    }

    private func checkEmail() async {
        isWorking = true
        defer { isWorking = false }
        do {
            if try await services.account.isEmailRegistered(trimmed(email)) {
                errorMessage = Self.emailTakenMessage
                return
            }
        } catch {
            // Couldn't check; creating the account checks again.
        }
        move(to: .profile)
    }

    /// Creates the account the first time it's needed; after that, saves name changes made by going
    /// back. Nil if that failed, with `errorMessage` saying why.
    private func ensureAccount() async -> User? {
        let firstName = trimmed(self.firstName)
        let lastName = trimmed(self.lastName)
        let nickname = trimmed(self.nickname).isEmpty ? nil : trimmed(self.nickname)
        do {
            if let existing = user {
                if existing.firstName != firstName || existing.lastName != lastName || existing.nickname != nickname {
                    user = try await services.account.updateProfile(
                        UpdateUserRequest(firstName: firstName, lastName: lastName, nickname: nickname), for: existing.id)
                }
            } else {
                user = try await services.account.createAccount(CreateUserRequest(
                    email: trimmed(email),
                    password: password,
                    firstName: firstName,
                    lastName: lastName,
                    nickname: nickname
                ))
            }
            return user
        } catch let error as APIError where error.code == .conflict {
            move(to: .credentials)
            errorMessage = Self.emailTakenMessage
        } catch {
            errorMessage = error.localizedDescription
        }
        return nil
    }

    static let emailTakenMessage = "There's already an account with this email. Sign in instead?"

    // MARK: Activities

    /// The standard list needs no account, so this works before one exists.
    func loadActivities() async {
        activitiesLoadError = nil
        do {
            let standard = try await services.activities.fetchStandardActivities()
            // Keep any typed in while the list was loading.
            activities = activities.filter(\.isCustom) + standard.map(ActivityChoice.init(standard:))
            hasLoadedActivities = true
        } catch {
            activitiesLoadError = error.localizedDescription
        }
    }

    var trimmedQuery: String {
        trimmed(query)
    }

    /// Matches for the search, without the defaults (they're always included).
    var searchResults: [ActivityChoice] {
        let pickable = activities.filter { !Self.isDefaultActivity($0.name) }
        guard !trimmedQuery.isEmpty else { return pickable }
        return pickable.filter { $0.name.localizedCaseInsensitiveContains(trimmedQuery) }
    }

    var selectedActivities: [ActivityChoice] {
        selectedIds.compactMap { id in activities.first { $0.id == id } }
    }

    /// The search turned up nothing, so the search button becomes "Add".
    var canAddSearchedActivity: Bool {
        !trimmedQuery.isEmpty && trimmedQuery.count <= Self.maxActivityNameLength
            && searchResults.isEmpty && !Self.isDefaultActivity(trimmedQuery)
    }

    /// The search is for "Free" or "Do not disturb", which everyone already has.
    var queryIsDefaultActivity: Bool {
        Self.isDefaultActivity(trimmedQuery)
    }

    var remainingActivityCount: Int {
        max(0, Self.requiredActivityCount - selectedIds.count)
    }

    func isSelected(_ activity: ActivityChoice) -> Bool {
        selectedIds.contains(activity.id)
    }

    func toggle(_ activity: ActivityChoice) {
        if let index = selectedIds.firstIndex(of: activity.id) {
            selectedIds.remove(at: index)
        } else {
            selectedIds.append(activity.id)
        }
    }

    /// Adds the searched-for name as the user's own activity and picks it. It's created with the account.
    func addSearchedActivity() {
        guard canAddSearchedActivity else { return }
        let activity = ActivityChoice(newNamed: trimmedQuery, defaultDurationMinutes: Self.customActivityMinutes)
        activities.insert(activity, at: 0)
        selectedIds.append(activity.id)
        query = ""
    }

    /// Creates the defaults and the typed-in picks as the user's own activities, then saves the picks.
    /// Rows made by an earlier attempt are reused.
    private func saveActivities(for user: User) async -> Bool {
        do {
            for item in Self.defaultActivities where defaultActivityIds[item.name] == nil {
                defaultActivityIds[item.name] = try await services.activities.createActivity(
                    name: item.name, durationMinutes: item.durationMinutes, for: user.id).id
            }
            for choice in selectedActivities where choice.isNew {
                let created = try await services.activities.createActivity(
                    name: choice.name, durationMinutes: choice.defaultDurationMinutes, for: user.id)
                replace(choice, with: ActivityChoice(custom: created))
            }
            let picked = selectedActivities
            _ = try await services.activities.saveActivities(
                customIds: Self.defaultActivityNames.compactMap { defaultActivityIds[$0] } + picked.compactMap(\.customId),
                standardNames: picked.filter { !$0.isCustom }.map(\.name),
                for: user.id
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func replace(_ old: ActivityChoice, with new: ActivityChoice) {
        if let index = activities.firstIndex(of: old) { activities[index] = new }
        if let index = selectedIds.firstIndex(of: old.id) { selectedIds[index] = new.id }
    }

    static func isDefaultActivity(_ name: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return defaultActivityNames.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    // MARK: Google Calendar

    /// Creates the account if needed, since the connection belongs to it, then asks the API where to
    /// send the user. Nil if either failed; `errorMessage` or `calendarState` says why.
    func startCalendarConnection() async -> CalendarConnection? {
        errorMessage = nil
        calendarState = .connecting
        guard let user = await ensureAccount() else {
            calendarState = .notConnected
            return nil
        }
        do {
            return try await services.calendar.startGoogleCalendarConnection(for: user.id)
        } catch {
            calendarState = .failed(error.localizedDescription)
            return nil
        }
    }

    /// Reads `?result=` from the URL the API sent the browser back to.
    func finishCalendarConnection(callbackURL: URL) {
        let result = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "result" }?.value
        switch result {
        case "connected":
            calendarState = .connected
            statusSources.insert(.calendar)
        case "denied":
            calendarState = .failed("Impromptu wasn't given access to your calendar. Try again, or skip for now.")
        case "expired":
            calendarState = .failed("The sign-in link expired. Try again.")
        default:
            calendarState = .failed("Couldn't connect Google Calendar. Try again, or skip for now.")
        }
    }

    /// The user closed the Google sign-in window.
    func cancelCalendarConnection() {
        calendarState = .notConnected
    }

    func calendarConnectionFailed(_ error: Error) {
        calendarState = .failed(error.localizedDescription)
    }

    // MARK: Status updates

    func setStatusSource(_ source: StatusSource, isOn: Bool) {
        if isOn {
            statusSources.insert(source)
        } else {
            statusSources.remove(source)
        }
    }

    private func finish(session: SessionViewModel) async {
        isWorking = true
        defer { isWorking = false }
        guard let user = await ensureAccount(), await saveActivities(for: user) else { return }
        services.statusPreferences.save(statusSources, for: user.id)
        session.completeRegistration(user)
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
