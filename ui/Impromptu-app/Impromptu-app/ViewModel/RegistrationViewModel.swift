//
//  RegistrationViewModel.swift
//  Impromptu-app
//

import Foundation
import Observation

/// The sign-up sheet. The account is created after the name step, because picking activities and
/// connecting a calendar need it; the session only switches to the home screen after the last step.
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
    /// Everything the user can pick: their own activities (from the database) on top, then the
    /// standard ones (the built-in list from `GET /activities`).
    private(set) var activities: [ActivityChoice] = []
    /// Picked activities, in the order they were picked. Excludes the defaults.
    private(set) var selectedIds: [ActivityChoice.ID] = []
    private(set) var activitiesLoadError: String?
    /// The list has come back, even if it was empty.
    private(set) var hasLoadedActivities = false
    private(set) var isAddingActivity = false

    private(set) var calendarState: CalendarState = .notConnected
    var statusSources: Set<StatusSource> = [.manual]

    private(set) var isWorking = false
    private(set) var errorMessage: String?
    /// Set once the account exists; there's no going back to the first two steps after that.
    private(set) var user: User?

    private let services: Services

    init(services: Services) {
        self.services = services
    }

    // MARK: Navigation

    var canGoBack: Bool {
        switch step {
        case .credentials, .activities: false
        case .profile: user == nil
        case .calendar, .statusSources: true
        }
    }

    var canContinue: Bool {
        guard !isWorking else { return false }
        switch step {
        case .credentials:
            return trimmed(email).contains("@") && password.count >= Self.minimumPasswordLength
        case .profile:
            return !trimmed(firstName).isEmpty && !trimmed(lastName).isEmpty
                && trimmed(nickname).count <= Self.maxNicknameLength
        case .activities:
            return selectedIds.count >= Self.requiredActivityCount && !isAddingActivity
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

    /// Does the current step's work, then moves on. The last step signs in.
    func advance(session: SessionViewModel) async {
        guard canContinue else { return }
        errorMessage = nil
        switch step {
        case .credentials:
            await checkEmail()
        case .profile:
            await createAccount()
        case .activities:
            if await saveActivities() { move(to: .calendar) }
        case .calendar:
            move(to: .statusSources)
        case .statusSources:
            finish(session: session)
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

    private func createAccount() async {
        isWorking = true
        defer { isWorking = false }
        let nickname = trimmed(nickname)
        do {
            user = try await services.account.createAccount(CreateUserRequest(
                email: trimmed(email),
                password: password,
                firstName: trimmed(firstName),
                lastName: trimmed(lastName),
                nickname: nickname.isEmpty ? nil : nickname
            ))
            move(to: .activities)
        } catch let error as APIError where error.code == .conflict {
            move(to: .credentials)
            errorMessage = Self.emailTakenMessage
            return
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        await loadActivities()
    }

    static let emailTakenMessage = "There's already an account with this email. Sign in instead?"

    // MARK: Activities

    func loadActivities() async {
        guard let user else { return }
        activitiesLoadError = nil
        do {
            async let standard = services.activities.fetchStandardActivities()
            // Only the user's own come from the database; a brand-new account usually has none.
            async let rows = services.activities.fetchActivities(for: user.id)
            let custom = ((try? await rows) ?? []).filter(\.isCustom)
            activities = custom.map(ActivityChoice.init(custom:)) + (try await standard).map(ActivityChoice.init(standard:))
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
            && searchResults.isEmpty && !Self.isDefaultActivity(trimmedQuery) && !isAddingActivity
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

    /// Creates the searched-for name as the user's own activity and picks it.
    func addSearchedActivity() async {
        guard canAddSearchedActivity, let user else { return }
        isAddingActivity = true
        defer { isAddingActivity = false }
        do {
            let activity = ActivityChoice(custom: try await services.activities.createActivity(
                name: trimmedQuery, durationMinutes: Self.customActivityMinutes, for: user.id))
            activities.insert(activity, at: 0)
            selectedIds.append(activity.id)
            query = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Saves the picks plus the defaults, creating the defaults first if this user doesn't have them yet.
    private func saveActivities() async -> Bool {
        guard let user else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            // The defaults are the user's own rows; reuse them if a previous attempt already made them.
            var defaultIds: [UUID] = []
            for item in Self.defaultActivities {
                if let existing = activities.first(where: {
                    $0.isCustom && $0.name.caseInsensitiveCompare(item.name) == .orderedSame
                })?.customId {
                    defaultIds.append(existing)
                } else {
                    let created = try await services.activities.createActivity(
                        name: item.name, durationMinutes: item.durationMinutes, for: user.id)
                    activities.insert(ActivityChoice(custom: created), at: 0)
                    defaultIds.append(created.id)
                }
            }
            let picked = selectedActivities
            _ = try await services.activities.saveActivities(
                customIds: defaultIds + picked.compactMap(\.customId),
                standardNames: picked.filter { !$0.isCustom }.map(\.name),
                for: user.id
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    static func isDefaultActivity(_ name: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return defaultActivityNames.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    // MARK: Google Calendar

    /// Asks the API where to send the user. Nil if that failed; `calendarState` says why.
    func startCalendarConnection() async -> CalendarConnection? {
        guard let user else { return nil }
        calendarState = .connecting
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

    private func finish(session: SessionViewModel) {
        guard let user else { return }
        services.statusPreferences.save(statusSources, for: user.id)
        session.completeRegistration(user)
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
