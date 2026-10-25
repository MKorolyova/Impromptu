//
//  Impromptu_appTests.swift
//  Impromptu-appTests
//
//  Created by Alekzander Brysch on 10/24/26.
//

import Foundation
import Testing
@testable import Impromptu_app

@MainActor
struct HomeViewModelTests {
    private let widgets = MockWidgetSyncService()

    private func makeViewModel(statuses: MockStatusService? = nil, people: MockPeopleService? = nil,
                               nearbyAlerts: MockNearbyAlerts? = nil) -> HomeViewModel {
        let services = Services(
            account: MockAccountService(),
            activities: MockActivityService(),
            friends: MockFriendService(),
            calendar: MockCalendarService(),
            statusPreferences: MockStatusPreferencesStore(),
            statuses: statuses ?? MockStatusService(),
            people: people ?? MockPeopleService(),
            nearbyAlerts: nearbyAlerts ?? MockNearbyAlerts(enabled: false),
            push: MockPushService(),
            noteRequests: MockNoteRequestService(),
            noteMonitor: MockNoteRequestMonitor(),
            location: MockLocationProvider(),
            router: AppRouter(),
            widgets: widgets
        )
        return HomeViewModel(user: SampleData.user, services: services)
    }

    @Test func nearbyLoadsWhenEnabledAndClearsWhenTurnedOff() async {
        let viewModel = makeViewModel(nearbyAlerts: MockNearbyAlerts(enabled: true))
        await viewModel.load()
        #expect(viewModel.nearby?.users.count == 3)
        #expect(viewModel.openNoteRequestCount == 1)

        await viewModel.setNearbyAlerts(false)
        #expect(!viewModel.isNearbyEnabled)
        #expect(viewModel.nearby == nil)
    }

    @Test func turningOnNearbyWithWhileUsingShowsNotice() async {
        let alerts = MockNearbyAlerts(enabled: false)
        alerts.locationAuthorization = .whileUsing
        let viewModel = makeViewModel(nearbyAlerts: alerts)
        await viewModel.load()
        #expect(viewModel.nearby == nil)

        await viewModel.setNearbyAlerts(true)
        #expect(viewModel.isNearbyEnabled)
        #expect(viewModel.nearbyNotice == .whileUsingOnly)
        #expect(viewModel.nearby?.users.isEmpty == false)
    }

    @Test func loadPopulatesFeedAndSyncsWidget() async {
        let viewModel = makeViewModel()
        await viewModel.load()

        #expect(viewModel.loadState == .loaded)
        #expect(viewModel.people.count == SampleData.people.count)
        #expect(viewModel.activePeople.count + viewModel.idlePeople.count == SampleData.people.count)
        #expect(viewModel.activePeople.allSatisfy { $0.activeStatus != nil })
        #expect(widgets.syncCount == 1)
        #expect(widgets.lastPeople.count == SampleData.people.count)
    }

    @Test func feedLeavesOutTheSignedInUser() async {
        let me = Person(id: SampleData.user.id, firstName: "Alex", lastName: "Rivera", nickname: nil, status: nil)
        let people = MockPeopleService()
        people.people.append(me)
        let viewModel = makeViewModel(people: people)
        await viewModel.load()

        #expect(!viewModel.people.contains { $0.id == SampleData.user.id })
    }

    @Test func updatingStatusUsesActivityLengthAndConfirms() async {
        let viewModel = makeViewModel(statuses: MockStatusService(status: nil))
        await viewModel.load()
        #expect(!viewModel.canPublishDraft)

        let activity = SampleData.activities[0]
        viewModel.draft.activity = activity
        viewModel.draft.note = "  Hi  "
        await viewModel.publishDraft()

        #expect(viewModel.myStatus?.activity.id == activity.id)
        #expect(viewModel.myStatus?.note == "Hi")
        let length = viewModel.myStatus.map { $0.expiresAt.timeIntervalSince($0.startedAt) } ?? 0
        #expect(abs(length - activity.defaultDuration) < 0.001)
        #expect(viewModel.showsUpdateConfirmation)
        #expect(widgets.lastStatus?.note == "Hi")

        await viewModel.clearStatus()
        #expect(viewModel.myStatus == nil)
        #expect(viewModel.draft == StatusDraft())
        #expect(widgets.lastStatus == nil)
    }

    @Test func composerStartsFromCurrentStatus() async {
        let viewModel = makeViewModel()
        await viewModel.load()

        #expect(viewModel.draft.activity?.id == viewModel.myStatus?.activity.id)
        #expect(viewModel.draft.note == viewModel.myStatus?.note)
    }

    @Test func dropDownListsSavedActivities() async {
        let viewModel = makeViewModel()
        await viewModel.load()

        // The mock saves the first five; the drafted current status is kept in the list too.
        let saved = Set(SampleData.activities.prefix(5).map(\.id))
        #expect(viewModel.myActivities.filter { saved.contains($0.id) }.count == 5)
        #expect(viewModel.myActivities.allSatisfy { saved.contains($0.id) || $0 == viewModel.draft.activity })
    }

    @Test func renamingUpdatesWidget() async {
        let viewModel = makeViewModel()
        await viewModel.load()
        var renamed = SampleData.user
        renamed.nickname = "Lex"
        viewModel.userDidChange(renamed)

        #expect(viewModel.user.displayName == "Lex")
        #expect(widgets.syncCount == 2)
    }

    @Test func customActivitiesAreAddedFirstAndDeletable() async throws {
        let viewModel = makeViewModel()
        await viewModel.load()

        let created = try #require(await viewModel.createActivity(name: "Hacking", durationMinutes: 90))
        #expect(viewModel.activities.first == created)

        await viewModel.deleteActivity(created)
        #expect(!viewModel.activities.contains(created))
    }
}

@MainActor
struct SessionViewModelTests {
    @Test func restoreWithoutStoredUserSignsOut() async {
        let session = SessionViewModel(services: .mock(signedIn: false))
        await session.restore()
        #expect(session.state == .signedOut)
    }

    @Test func restoreLoadsStoredUser() async {
        let session = SessionViewModel(services: .mock(signedIn: true))
        await session.restore()
        #expect(session.user == SampleData.user)
    }

    @Test func logInWithValidCredentialsSignsIn() async throws {
        let session = SessionViewModel(services: .mock(signedIn: false))
        try await session.logIn(email: SampleData.user.email.uppercased(), password: MockAccountService.password)
        #expect(session.user == SampleData.user)
    }

    @Test func signingInRegistersForPushAndSigningOutUnregisters() async throws {
        let push = MockPushService()
        let session = SessionViewModel(services: Services.mock(signedIn: false).replacing(push: push))
        try await session.logIn(email: SampleData.user.email, password: MockAccountService.password)
        #expect(push.registerCount == 1)

        session.signOut()
        try await Task.sleep(for: .milliseconds(50))
        #expect(push.unregisteredUserIds == [SampleData.user.id])
    }

    @Test func restoringRegistersForPush() async {
        let push = MockPushService()
        let session = SessionViewModel(services: Services.mock(signedIn: true).replacing(push: push))
        await session.restore()
        #expect(push.registerCount == 1)
    }

    @Test func logInWithWrongPasswordShowsServerMessage() async {
        let session = SessionViewModel(services: .mock(signedIn: false))
        let viewModel = LoginViewModel()
        viewModel.email = SampleData.user.email
        viewModel.password = "wrong"

        await viewModel.submit(to: session)
        #expect(session.user == nil)
        #expect(viewModel.errorMessage == "Invalid email or password")
    }
}

@MainActor
struct RegistrationViewModelTests {
    private let account = MockAccountService(signedIn: false)
    private let activities = MockActivityService()
    private let calendar = MockCalendarService()
    private let preferences = MockStatusPreferencesStore()

    private var services: Services {
        Services(
            account: account,
            activities: activities,
            friends: MockFriendService(),
            calendar: calendar,
            statusPreferences: preferences,
            statuses: MockStatusService(),
            people: MockPeopleService(),
            nearbyAlerts: MockNearbyAlerts(enabled: false),
            push: MockPushService(),
            noteRequests: MockNoteRequestService(),
            noteMonitor: MockNoteRequestMonitor(),
            location: MockLocationProvider(),
            router: AppRouter(),
            widgets: MockWidgetSyncService()
        )
    }

    /// Fills in the first two steps. Nothing is saved yet.
    private func fillInAccount(_ viewModel: RegistrationViewModel, session: SessionViewModel) async {
        viewModel.email = "new@example.com"
        viewModel.password = "password1"
        await viewModel.advance(session: session)
        viewModel.firstName = " Ada "
        viewModel.lastName = "Lovelace"
        await viewModel.advance(session: session)
    }

    /// From the activities step: picks five standard ones and goes to the last step.
    private func pickActivitiesAndSkipCalendar(_ viewModel: RegistrationViewModel, session: SessionViewModel) async {
        viewModel.activities.filter { !$0.isCustom }.prefix(5).forEach(viewModel.toggle)
        await viewModel.advance(session: session)
        await viewModel.advance(session: session)
    }

    @Test func takenEmailStopsAtFirstStep() async {
        let session = SessionViewModel(services: services)
        let viewModel = RegistrationViewModel(services: services)
        viewModel.email = SampleData.user.email
        viewModel.password = "password1"
        await viewModel.advance(session: session)

        #expect(viewModel.step == .credentials)
        #expect(viewModel.errorMessage == RegistrationViewModel.emailTakenMessage)
    }

    @Test func everyStepCanBeRevisitedBeforeTheAccountExists() async {
        let session = SessionViewModel(services: services)
        let viewModel = RegistrationViewModel(services: services)
        await fillInAccount(viewModel, session: session)

        #expect(viewModel.step == .activities)
        #expect(viewModel.user == nil)
        #expect(account.user.id == SampleData.user.id)
        #expect(viewModel.activities.count == activities.standardActivities.count)

        viewModel.goBack()
        viewModel.goBack()
        #expect(viewModel.step == .credentials)
        #expect(!viewModel.canGoBack)

        viewModel.email = "other@example.com"
        await viewModel.advance(session: session)
        await viewModel.advance(session: session)
        #expect(viewModel.step == .activities)
        #expect(viewModel.user == nil)
    }

    @Test func needsFiveActivities() async {
        let session = SessionViewModel(services: services)
        let viewModel = RegistrationViewModel(services: services)
        await fillInAccount(viewModel, session: session)

        viewModel.activities.prefix(4).forEach(viewModel.toggle)
        #expect(!viewModel.canContinue)
        #expect(viewModel.remainingActivityCount == 1)

        viewModel.toggle(viewModel.activities[4])
        #expect(viewModel.canContinue)
        await viewModel.advance(session: session)

        #expect(viewModel.step == .calendar)
        #expect(activities.savedStandardNames.isEmpty)
    }

    @Test func standardListComesFromBuiltInEndpointEvenWithEmptyDatabase() async {
        activities.activities = []
        let session = SessionViewModel(services: services)
        let viewModel = RegistrationViewModel(services: services)
        await fillInAccount(viewModel, session: session)

        #expect(viewModel.hasLoadedActivities)
        #expect(viewModel.activities.map(\.name) == activities.standardActivities.map(\.name))
        #expect(viewModel.activities.allSatisfy { !$0.isCustom })
    }

    @Test func searchWithNoMatchOffersAdd() async {
        let session = SessionViewModel(services: services)
        let viewModel = RegistrationViewModel(services: services)
        await fillInAccount(viewModel, session: session)

        viewModel.query = "Cod"
        #expect(!viewModel.searchResults.isEmpty)
        #expect(!viewModel.canAddSearchedActivity)

        viewModel.query = "Free"
        #expect(viewModel.queryIsDefaultActivity)
        #expect(!viewModel.canAddSearchedActivity)

        viewModel.query = "Kitesurfing"
        #expect(viewModel.canAddSearchedActivity)
        viewModel.addSearchedActivity()
        #expect(viewModel.selectedActivities.map(\.name) == ["Kitesurfing"])
        #expect(viewModel.activities.first?.isCustom == true)
        #expect(viewModel.query.isEmpty)
        // Not on the server until the account is.
        #expect(!activities.activities.contains { $0.name == "Kitesurfing" })
    }

    @Test func calendarCreatesTheAccountAndReadsTheCallback() async {
        let session = SessionViewModel(services: services)
        let viewModel = RegistrationViewModel(services: services)
        await fillInAccount(viewModel, session: session)

        #expect(await viewModel.startCalendarConnection() != nil)
        #expect(viewModel.user?.email == "new@example.com")
        #expect(viewModel.calendarState == .connecting)
        #expect(session.user == nil)

        viewModel.finishCalendarConnection(callbackURL: URL(string: "impromptu://google-calendar?result=denied")!)
        guard case .failed = viewModel.calendarState else {
            Issue.record("Expected a failure, got \(viewModel.calendarState)")
            return
        }
        viewModel.finishCalendarConnection(callbackURL: URL(string: "impromptu://google-calendar?result=connected")!)
        #expect(viewModel.calendarState == .connected)
        #expect(viewModel.statusSources.contains(.calendar))
    }

    @Test func nameChangedAfterAccountExistsIsSavedAtFinish() async {
        let session = SessionViewModel(services: services)
        let viewModel = RegistrationViewModel(services: services)
        await fillInAccount(viewModel, session: session)
        _ = await viewModel.startCalendarConnection()
        viewModel.cancelCalendarConnection()

        viewModel.goBack()
        viewModel.goBack()
        #expect(viewModel.step == .credentials)
        #expect(viewModel.isAccountCreated)
        // Locked, but you can still step through.
        #expect(viewModel.canContinue)
        await viewModel.advance(session: session)
        viewModel.nickname = "Countess"
        await viewModel.advance(session: session)
        await pickActivitiesAndSkipCalendar(viewModel, session: session)
        await viewModel.advance(session: session)

        #expect(account.user.nickname == "Countess")
        #expect(session.user?.displayName == "Countess")
    }

    @Test func finishingCreatesAccountSavesEverythingAndSignsIn() async throws {
        let session = SessionViewModel(services: services)
        let viewModel = RegistrationViewModel(services: services)
        await fillInAccount(viewModel, session: session)
        viewModel.query = "Kitesurfing"
        viewModel.addSearchedActivity()
        viewModel.activities.filter { !$0.isCustom }.prefix(4).forEach(viewModel.toggle)
        await viewModel.advance(session: session)
        await viewModel.advance(session: session)
        #expect(viewModel.step == .statusSources)

        viewModel.setStatusSource(.location, isOn: true)
        await viewModel.advance(session: session)

        let userId = try #require(viewModel.user?.id)
        #expect(account.user.firstName == "Ada")
        #expect(session.user?.id == userId)
        #expect(preferences.sources(for: userId) == [.manual, .location])

        let kitesurfing = try #require(activities.activities.first { $0.name == "Kitesurfing" })
        #expect(kitesurfing.isCustom)
        let savedNames = Set(activities.activities.filter { activities.savedIds.contains($0.id) }.map(\.name))
        #expect(savedNames.isSuperset(of: RegistrationViewModel.defaultActivityNames + ["Kitesurfing"]))
        #expect(activities.savedStandardNames == SampleData.activities.prefix(4).map(\.name))
        #expect(activities.savedIds.count == 7)
    }
}

@MainActor
struct SettingsViewModelTests {
    private let friends = MockFriendService()

    private func makeViewModel() -> (SettingsViewModel, SessionViewModel) {
        let services = Services(
            account: MockAccountService(),
            activities: MockActivityService(),
            friends: friends,
            calendar: MockCalendarService(),
            statusPreferences: MockStatusPreferencesStore(),
            statuses: MockStatusService(),
            people: MockPeopleService(),
            nearbyAlerts: MockNearbyAlerts(enabled: false),
            push: MockPushService(),
            noteRequests: MockNoteRequestService(),
            noteMonitor: MockNoteRequestMonitor(),
            location: MockLocationProvider(),
            router: AppRouter(),
            widgets: MockWidgetSyncService()
        )
        let session = SessionViewModel(services: services)
        session.completeRegistration(SampleData.user)
        return (SettingsViewModel(user: SampleData.user, services: services), session)
    }

    @Test func savingNameUpdatesSession() async {
        let (viewModel, session) = makeViewModel()
        #expect(!viewModel.canSaveProfile)

        viewModel.nickname = " Lex "
        #expect(viewModel.canSaveProfile)
        await viewModel.saveProfile(session: session)

        #expect(session.user?.nickname == "Lex")
        #expect(session.user?.displayName == "Lex")
        #expect(!viewModel.hasProfileChanges)
    }

    @Test func addingByEmailGrantsOnlyThatList() async throws {
        let (viewModel, _) = makeViewModel()
        await viewModel.loadFriends()
        viewModel.startAdding(to: .location)
        viewModel.friendEmail = "PRIYA@example.com"

        #expect(await viewModel.addFriendByEmail())
        let priya = try #require(viewModel.friends.first { $0.firstName == "Priya" })
        #expect(priya.canSeeLocation)
        #expect(!priya.canSeeNotes)
        #expect(viewModel.addingTo == nil)
    }

    @Test func unknownEmailExplainsWhy() async {
        let (viewModel, _) = makeViewModel()
        viewModel.startAdding(to: .notes)
        viewModel.friendEmail = "nobody@example.com"

        #expect(!(await viewModel.addFriendByEmail()))
        #expect(viewModel.addFriendError?.contains("No one") == true)
        #expect(viewModel.addingTo == .notes)
    }

    @Test func removingFromLastListRemovesFriend() async throws {
        let (viewModel, _) = makeViewModel()
        await viewModel.loadFriends()
        let sam = try #require(viewModel.friends.first { $0.firstName == "Sam" })

        await viewModel.remove(sam, from: .location)
        #expect(viewModel.friends(in: .location).isEmpty)
        #expect(viewModel.friends(in: .notes).contains { $0.id == sam.id })

        let updated = try #require(viewModel.friends.first { $0.id == sam.id })
        await viewModel.remove(updated, from: .notes)
        #expect(!viewModel.friends.contains { $0.id == sam.id })
    }

    @Test func keepsAtLeastOneStatusSource() {
        let (viewModel, _) = makeViewModel()
        viewModel.setStatusSource(.manual, isOn: false)
        #expect(viewModel.statusSources == [.manual])
    }
}

struct BrandTests {
    @Test func gmtOffsetLabels() {
        let winter = Date(timeIntervalSince1970: 1_800_000_000) // January
        #expect(GMTOffset.label(for: "America/Bogota", at: winter) == "GMT-5")
        #expect(GMTOffset.label(for: "Asia/Kolkata", at: winter) == "GMT+5:30")
        #expect(GMTOffset.label(for: "UTC", at: winter) == "GMT")
        #expect(GMTOffset.label(for: "Not/AZone") == nil)
    }

    @Test func runningGetsRunnerSymbol() {
        #expect(ActivitySymbol.name(for: "Running") == "figure.run")
        #expect(ActivitySymbol.name(for: "Running errands") == "bag.fill")
        #expect(ActivitySymbol.name(for: "Do not disturb") == "moon.fill")
        #expect(ActivitySymbol.name(for: "Free") == "hand.wave.fill")
    }
}

struct SharedStoreTests {
    @Test func snapshotRoundTrips() throws {
        let store = SharedStore(directory: URL.temporaryDirectory.appending(path: UUID().uuidString))
        let snapshot = WidgetSnapshot.placeholder

        try store.save(snapshot, for: .widgetSnapshot)
        let loaded = try #require(store.load(.widgetSnapshot))
        #expect(loaded.friends.map(\.id) == snapshot.friends.map(\.id))
        #expect(loaded.myStatus?.activityName == snapshot.myStatus?.activityName)

        store.remove(.widgetSnapshot)
        #expect(store.load(.widgetSnapshot) == nil)
    }
}

/// Payloads shaped exactly like api/openapi.yaml.
@MainActor
struct APIContractTests {
    private struct StatusesEnvelope: Decodable { var statuses: [Status] }
    private struct ActivitiesEnvelope: Decodable { var activities: [Activity] }
    private struct UserEnvelope: Decodable { var user: User }

    @Test func decodesStatusList() throws {
        let json = Data(#"""
        {"statuses":[{"id":"7f1b7c4e-8a0e-4c55-9d0e-0b6c2a1d9f10","userId":"7f1b7c4e-8a0e-4c55-9d0e-0b6c2a1d9f11",
          "note":null,"source":"MANUAL","startedAt":"2026-10-24T19:54:00.123Z","expiresAt":"2026-10-24T21:54:00.123Z",
          "createdAt":"2026-10-24T19:54:00.123Z","updatedAt":"2026-10-24T19:54:00.123Z",
          "activity":{"id":"7f1b7c4e-8a0e-4c55-9d0e-0b6c2a1d9f12","name":"Coding","iconId":null,"isCustom":false}}]}
        """#.utf8)
        let status = try #require(try JSONDecoder.api.decode(StatusesEnvelope.self, from: json).statuses.first)
        #expect(status.activity.name == "Coding")
        #expect(status.expiresAt.timeIntervalSince(status.startedAt) == 7200)
    }

    @Test func decodesActivityList() throws {
        let json = Data(#"""
        {"activities":[{"id":"7f1b7c4e-8a0e-4c55-9d0e-0b6c2a1d9f12","ownerId":null,"name":"Coding","iconId":null,
          "defaultDurationMinutes":120,"isCustom":false,"createdAt":"2026-10-24T19:54:00.123Z","updatedAt":"2026-10-24T19:54:00.123Z"}]}
        """#.utf8)
        let activities = try JSONDecoder.api.decode(ActivitiesEnvelope.self, from: json).activities
        #expect(activities.first?.defaultDurationMinutes == 120)
        #expect(activities.first?.ownerId == nil)
    }

    @Test func decodesUser() throws {
        let json = Data(#"""
        {"user":{"id":"7f1b7c4e-8a0e-4c55-9d0e-0b6c2a1d9f11","email":"a@b.co","firstName":"Ada","lastName":"L",
          "nickname":null,"timezone":"America/Chicago","createdAt":"2026-10-24T19:54:00.123Z","updatedAt":"2026-10-24T19:54:00.123Z"}}
        """#.utf8)
        #expect(try JSONDecoder.api.decode(UserEnvelope.self, from: json).user.displayName == "Ada L")
    }

    @Test func decodesPeopleList() throws {
        struct PeopleEnvelope: Decodable { var users: [Person] }
        let json = Data(#"""
        {"users":[
          {"id":"7f1b7c4e-8a0e-4c55-9d0e-0b6c2a1d9f11","firstName":"Ada","lastName":"L","nickname":null,
           "status":{"id":"7f1b7c4e-8a0e-4c55-9d0e-0b6c2a1d9f10","userId":"7f1b7c4e-8a0e-4c55-9d0e-0b6c2a1d9f11",
             "note":"hi","source":"MANUAL","startedAt":"2026-10-24T19:54:00.123Z","expiresAt":"2099-10-24T21:54:00.123Z",
             "createdAt":"2026-10-24T19:54:00.123Z","updatedAt":"2026-10-24T19:54:00.123Z",
             "activity":{"id":"7f1b7c4e-8a0e-4c55-9d0e-0b6c2a1d9f12","name":"Coding","iconId":null,"isCustom":false}}},
          {"id":"7f1b7c4e-8a0e-4c55-9d0e-0b6c2a1d9f13","firstName":"Bo","lastName":"M","nickname":"B","status":null}
        ]}
        """#.utf8)
        let people = try JSONDecoder.api.decode(PeopleEnvelope.self, from: json).users
        #expect(people.first?.activeStatus?.note == "hi")
        #expect(people.last?.status == nil)
        #expect(people.last?.displayName == "B")
    }

    @Test func decodesErrorBody() throws {
        let json = Data(#"{"error":{"code":"CONFLICT","message":"An account with this email already exists"}}"#.utf8)
        let body = try JSONDecoder.api.decode(APIErrorBody.self, from: json)
        #expect(body.error.code == .conflict)
    }

    @Test func createStatusOmitsUnsetFields() throws {
        let request = CreateStatusRequest(activityId: UUID(), note: nil, expiresAt: nil)
        let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder.api.encode(request)) as? [String: Any])
        #expect(Set(object.keys) == ["activityId"])
    }

    @Test func decodesFriend() throws {
        struct FriendsEnvelope: Decodable { var friends: [Friend] }
        let json = Data(#"""
        {"friends":[{"id":"7f1b7c4e-8a0e-4c55-9d0e-0b6c2a1d9f13","firstName":"Bo","lastName":"M","nickname":null,
          "canSeeLocation":true,"canSeeNotes":false}]}
        """#.utf8)
        let friend = try #require(try JSONDecoder.api.decode(FriendsEnvelope.self, from: json).friends.first)
        #expect(friend.canSeeLocation && !friend.canSeeNotes)
        #expect(friend.displayName == "Bo M")
    }

    @Test func updateUserAlwaysSendsNickname() throws {
        let request = UpdateUserRequest(firstName: "Ada", lastName: "L", nickname: nil)
        let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder.api.encode(request)) as? [String: Any])
        #expect(Set(object.keys) == ["firstName", "lastName", "nickname"])
        #expect(object["nickname"] is NSNull)
    }

    @Test func friendAccessOmitsUnchangedFields() throws {
        let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder.api.encode(FriendAccess(canSeeNotes: false))) as? [String: Any])
        #expect(Set(object.keys) == ["canSeeNotes"])
    }

    @Test func newRoutesMatchSpec() throws {
        let userId = UUID(uuidString: "7F1B7C4E-8A0E-4C55-9D0E-0B6C2A1D9F11")!
        let friendId = UUID(uuidString: "7F1B7C4E-8A0E-4C55-9D0E-0B6C2A1D9F13")!
        let base = "users/7f1b7c4e-8a0e-4c55-9d0e-0b6c2a1d9f11"

        let update = try Endpoint.updateUser(UpdateUserRequest(firstName: "A", lastName: "B"), for: userId)
        #expect(update.method == .patch && update.path == base)
        let saved = try Endpoint.replaceSavedActivities(ReplaceSavedActivitiesRequest(activityIds: []), for: userId)
        #expect(saved.method == .put && saved.path == "\(base)/saved-activities")
        let friend = try Endpoint.updateFriend(friendId, access: FriendAccess(canSeeLocation: true), for: userId)
        #expect(friend.method == .patch && friend.path == "\(base)/friends/7f1b7c4e-8a0e-4c55-9d0e-0b6c2a1d9f13")
        #expect(Endpoint.removeFriend(friendId, for: userId).method == .delete)
        #expect(Endpoint.connectGoogleCalendar(for: userId).path == "\(base)/google-calendar")
        #expect(try Endpoint.searchUsers(SearchUsersRequest(email: "a@b.co")).path == "users/search")

        let saveToken = try Endpoint.saveDeviceToken(SaveDeviceTokenRequest(token: "ab", environment: .production), for: userId)
        #expect(saveToken.method == .post && saveToken.path == "\(base)/device-tokens")
        #expect(try JSONDecoder().decode([String: String].self, from: try #require(saveToken.body))
                == ["token": "ab", "environment": "PRODUCTION"])
        let removeToken = try Endpoint.deleteDeviceToken(DeleteDeviceTokenRequest(token: "ab"), for: userId)
        // The token goes in the body, not the URL.
        #expect(removeToken.method == .delete && removeToken.path == "\(base)/device-tokens")
        #expect(try JSONDecoder().decode([String: String].self, from: try #require(removeToken.body)) == ["token": "ab"])
    }

    @Test func routesMatchSpec() {
        let userId = UUID(uuidString: "7F1B7C4E-8A0E-4C55-9D0E-0B6C2A1D9F11")!
        let statusId = UUID(uuidString: "7F1B7C4E-8A0E-4C55-9D0E-0B6C2A1D9F10")!
        #expect(Endpoint.user(userId).path == "users/7f1b7c4e-8a0e-4c55-9d0e-0b6c2a1d9f11")
        let login = try? Endpoint.login(LoginRequest(email: "a@b.co", password: "pw"))
        #expect(login?.method == .post)
        #expect(login?.path == "auth/login")
        #expect(Endpoint.statuses(for: userId, activeOnly: true).queryItems == [URLQueryItem(name: "active", value: "true")])
        let delete = Endpoint.deleteStatus(statusId, for: userId)
        #expect(delete.method == .delete)
        #expect(delete.path == "users/7f1b7c4e-8a0e-4c55-9d0e-0b6c2a1d9f11/statuses/7f1b7c4e-8a0e-4c55-9d0e-0b6c2a1d9f10")
    }
}

struct NearbyAlertPolicyTests {
    private let coding = UUID()
    private let sam = UUID(), jo = UUID(), priya = UUID()
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func firstMatchNotifies() {
        let (decision, state) = NearbyAlertPolicy.evaluate(state: .init(), activityId: coding, matchingUserIds: [sam], now: start)
        #expect(decision == .notify(newUserIds: [sam]))
        #expect(state.announcedUserIds == [sam])
        #expect(state.lastNotifiedAt == start)
    }

    @Test func sameUsersAnHourLaterSendNothing() {
        let (_, first) = NearbyAlertPolicy.evaluate(state: .init(), activityId: coding, matchingUserIds: [sam, jo], now: start)
        let (decision, _) = NearbyAlertPolicy.evaluate(state: first, activityId: coding, matchingUserIds: [jo, sam],
                                                       now: start.addingTimeInterval(2 * 3600))
        #expect(decision == .skip(.nothingNew))
    }

    @Test func newUserWithinTheMinuteWaitsThenNotifies() {
        let (_, first) = NearbyAlertPolicy.evaluate(state: .init(), activityId: coding, matchingUserIds: [sam], now: start)

        let (early, waiting) = NearbyAlertPolicy.evaluate(state: first, activityId: coding, matchingUserIds: [sam, jo],
                                                          now: start.addingTimeInterval(30))
        #expect(early == .skip(.tooSoon))
        #expect(!waiting.announcedUserIds.contains(jo))

        let (later, _) = NearbyAlertPolicy.evaluate(state: waiting, activityId: coding, matchingUserIds: [sam, jo],
                                                    now: start.addingTimeInterval(61))
        #expect(later == .notify(newUserIds: [jo]))
    }

    @Test func changingActivityStartsOverButKeepsTimeLimit() {
        let (_, first) = NearbyAlertPolicy.evaluate(state: .init(), activityId: coding, matchingUserIds: [sam], now: start)
        let studying = UUID()

        let (soon, rebased) = NearbyAlertPolicy.evaluate(state: first, activityId: studying, matchingUserIds: [sam],
                                                         now: start.addingTimeInterval(30))
        #expect(soon == .skip(.tooSoon))
        #expect(rebased.activityId == studying)
        #expect(rebased.announcedUserIds.isEmpty)

        let (later, _) = NearbyAlertPolicy.evaluate(state: rebased, activityId: studying, matchingUserIds: [sam],
                                                    now: start.addingTimeInterval(2 * 3600))
        #expect(later == .notify(newUserIds: [sam]))
    }

    @Test func noStatusNeverNotifies() {
        let (decision, _) = NearbyAlertPolicy.evaluate(state: .init(), activityId: nil, matchingUserIds: [sam], now: start)
        #expect(decision == .skip(.noStatus))
    }
}

@MainActor
struct NearbyAlertMessageTests {
    private func person(_ name: String) -> Person {
        Person(id: UUID(), firstName: name, lastName: "X", nickname: nil, status: nil)
    }

    @Test func onePerson() {
        let message = NearbyAlertMessage(newPeople: [person("Sam")], totalCount: 1, activityName: "Grabbing coffee")
        #expect(message.title == "Sam is nearby")
        #expect(message.body == "Sam is also grabbing coffee within 3 miles.")
    }

    @Test func severalPeopleWithOthersAlreadyAnnounced() {
        let message = NearbyAlertMessage(newPeople: ["Sam", "Jo", "Priya"].map(person), totalCount: 5, activityName: "Coding")
        #expect(message.title == "3 new people nearby")
        #expect(message.body == "Sam, Jo and 1 more are also coding within 3 miles. 5 people nearby in all.")
    }
}

@MainActor
struct NearbyAlertsServiceTests {
    private let api = MockNearbyService()
    private let location = MockLocationProvider()
    private let notifications = MockNotificationService()
    /// Unavailable unless a test says otherwise, as on a build from a free developer team.
    private let push = MockPushService()
    private let defaults = UserDefaults(suiteName: "NearbyAlertsServiceTests-\(UUID().uuidString)")!

    private func makeService(now: @escaping () -> Date = { .now }) -> NearbyAlertsService {
        NearbyAlertsService(account: MockAccountService(), api: api, location: location,
                            notifications: notifications, push: push, defaults: defaults, now: now)
    }

    @Test func enablingStartsMonitoring() async {
        let service = makeService()
        let outcome = await service.enable()
        #expect(outcome.isEnabled)
        #expect(service.isEnabled)
        #expect(location.isMonitoring)
    }

    @Test func deniedLocationLeavesAlertsOff() async {
        location.authorization = .denied
        let service = makeService()
        let outcome = await service.enable()
        #expect(!outcome.isEnabled)
        #expect(!service.isEnabled)
    }

    @Test func enablingAsksToShowNotifications() async {
        notifications.authorized = false
        let service = makeService()
        let outcome = await service.enable()
        // Location is what turns alerts on; without notifications they just can't be shown.
        #expect(outcome.isEnabled)
        #expect(!outcome.notificationsAllowed)
    }

    @Test func withPushTheServerNotifiesNotThePhone() async throws {
        push.isAvailable = true
        let service = makeService()
        _ = await service.enable()

        await service.performBackgroundCheck()
        _ = try await service.refreshInForeground()
        #expect(api.sharedLocations.count == 2)
        #expect(notifications.posted.isEmpty)
    }

    @Test func withoutPushThePhoneNotifiesOnceForSamePeople() async {
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let service = makeService(now: { clock })
        _ = await service.enable()

        await service.performBackgroundCheck()
        #expect(api.sharedLocations.count == 1)
        #expect(notifications.posted.count == 1)
        #expect(notifications.posted.first?.route == .nearbyPeople)
        #expect(notifications.posted.first?.title == "3 new people nearby")

        clock.addTimeInterval(2 * 3600)
        await service.performBackgroundCheck()
        #expect(notifications.posted.count == 1)
    }

    @Test func withoutPushNewMatchesPopUpWhileTheAppIsOpen() async throws {
        let service = makeService()
        _ = await service.enable()

        let result = try await service.refreshInForeground()
        #expect(result.users.count == 3)
        #expect(notifications.posted.count == 1)
    }

    @Test func withoutNotificationPermissionNothingIsPosted() async {
        notifications.authorized = false
        let service = makeService()
        _ = await service.enable()

        await service.performBackgroundCheck()
        #expect(api.sharedLocations.count == 1)
        #expect(notifications.posted.isEmpty)
    }

    @Test func significantLocationChangeIsReported() async throws {
        let service = makeService()
        _ = await service.enable()

        location.onUpdate?(Coordinate(latitude: 30.29, longitude: -97.74))
        try await Task.sleep(for: .milliseconds(50))
        #expect(api.sharedLocations.last == Coordinate(latitude: 30.29, longitude: -97.74))
    }

    @Test func foregroundRefreshSharesLocationAndReturnsMatchesWithinThreeMiles() async throws {
        let service = makeService()
        _ = await service.enable()

        let result = try await service.refreshInForeground()
        #expect(result.users.count == 3)
        #expect(api.sharedLocations.count == 1)
        #expect(NearbyAlertsService.radiusMeters == 4828)
    }

    @Test func nothingIsSharedWhileOff() async {
        let service = makeService()
        await service.performBackgroundCheck()
        #expect(api.sharedLocations.isEmpty)
    }

    @Test func disablingStopsSharingOnServer() async {
        let service = makeService()
        _ = await service.enable()
        await service.disable(userId: SampleData.user.id)

        #expect(!service.isEnabled)
        #expect(!location.isMonitoring)
        #expect(api.stopSharingCount == 1)
    }
}

@MainActor
struct PushNotificationServiceTests {
    private let client = RecordingAPIClient()
    private let defaults = UserDefaults(suiteName: "PushNotificationServiceTests-\(UUID().uuidString)")!

    @Test func availableOnceIOSGivesATokenAndNotAfterItRefuses() async {
        let service = PushNotificationService(account: MockAccountService(), client: client, defaults: defaults, requestToken: {})
        #expect(!service.isAvailable)
        await service.didReceiveDeviceToken(Data([0x01]))
        #expect(service.isAvailable)
        // Remembered for the next launch.
        #expect(PushNotificationService(account: MockAccountService(), client: client, defaults: defaults, requestToken: {}).isAvailable)

        service.didFailToRegister()
        #expect(!service.isAvailable)
    }

    @Test func tokenIsRegisteredAsHexForTheSignedInUser() async throws {
        var requests = 0
        let service = PushNotificationService(account: MockAccountService(), client: client, defaults: defaults, requestToken: { requests += 1 })
        service.register()
        #expect(requests == 1)

        await service.didReceiveDeviceToken(Data([0x0a, 0xff, 0x01]))
        let sent = try #require(client.sent.first)
        #expect(sent.method == .post)
        #expect(sent.path == "users/\(SampleData.user.id.pathComponent)/device-tokens")
        // Tests build in Debug, which gets sandbox tokens.
        #expect(try JSONDecoder().decode([String: String].self, from: try #require(sent.body))
                == ["token": "0aff01", "environment": "SANDBOX"])
    }

    @Test func tokenArrivingWhileSignedOutIsKeptButNotSent() async {
        let service = PushNotificationService(account: MockAccountService(signedIn: false), client: client, defaults: defaults, requestToken: {})
        await service.didReceiveDeviceToken(Data([0x01]))
        #expect(service.deviceToken == "01")
        #expect(client.sent.isEmpty)
    }

    @Test func unregisteringRemovesThisDevicesToken() async throws {
        let service = PushNotificationService(account: MockAccountService(), client: client, defaults: defaults, requestToken: {})
        await service.unregister(userId: SampleData.user.id)
        // Nothing to remove before iOS has handed over a token.
        #expect(client.sent.isEmpty)

        await service.didReceiveDeviceToken(Data([0xab, 0xcd]))
        await service.unregister(userId: SampleData.user.id)
        let removal = try #require(client.sent.last)
        #expect(removal.method == .delete)
        #expect(try JSONDecoder().decode([String: String].self, from: try #require(removal.body)) == ["token": "abcd"])
    }
}

@MainActor
struct NearbyContractTests {
    @Test func decodesNearbyResponse() throws {
        let json = Data(#"""
        {"activity":{"id":"7f1b7c4e-8a0e-4c55-9d0e-0b6c2a1d9f12","name":"Coding","iconId":null,"isCustom":false},
         "radiusMeters":1600,
         "users":[{"id":"7f1b7c4e-8a0e-4c55-9d0e-0b6c2a1d9f11","firstName":"Ada","lastName":"L","nickname":null,
           "status":{"id":"7f1b7c4e-8a0e-4c55-9d0e-0b6c2a1d9f10","userId":"7f1b7c4e-8a0e-4c55-9d0e-0b6c2a1d9f11",
             "note":null,"source":"MANUAL","startedAt":"2026-10-24T19:54:00.123Z","expiresAt":"2099-10-24T21:54:00.123Z",
             "createdAt":"2026-10-24T19:54:00.123Z","updatedAt":"2026-10-24T19:54:00.123Z",
             "activity":{"id":"7f1b7c4e-8a0e-4c55-9d0e-0b6c2a1d9f12","name":"Coding","iconId":null,"isCustom":false}}}]}
        """#.utf8)
        let result = try JSONDecoder.api.decode(NearbyResult.self, from: json)
        #expect(result.activity?.name == "Coding")
        #expect(result.users.first?.activeStatus != nil)

        let none = try JSONDecoder.api.decode(NearbyResult.self, from: Data(#"{"activity":null,"radiusMeters":1600,"users":[]}"#.utf8))
        #expect(none.activity == nil)
    }

    @Test func routes() throws {
        let userId = UUID(uuidString: "7F1B7C4E-8A0E-4C55-9D0E-0B6C2A1D9F11")!
        let update = try Endpoint.updateLocation(UpdateLocationRequest(latitude: 30.28, longitude: -97.73, accuracyMeters: nil), for: userId)
        #expect(update.method == .put)
        #expect(update.path == "users/7f1b7c4e-8a0e-4c55-9d0e-0b6c2a1d9f11/location")
        #expect(Endpoint.nearby(for: userId, radiusMeters: NearbyAlertsService.radiusMeters).queryItems
                == [URLQueryItem(name: "radiusMeters", value: "4828")])
        #expect(Endpoint.people.path == "feed")
    }
}

@MainActor
struct NoteActivityTrackerTests {
    private let sam = SampleData.people[0], jo = SampleData.people[1]

    private func inbox(incoming: [NoteRequest] = [], outgoing: [NoteRequest] = []) -> NoteInbox {
        NoteInbox(incoming: incoming, outgoing: outgoing)
    }

    @Test func firstPollRecordsWithoutAnnouncing() {
        let request = SampleData.noteRequest(direction: .incoming, with: sam)
        let (changes, state) = NoteActivityTracker.diff(inbox(incoming: [request]), since: NoteActivityState())
        #expect(changes.isEmpty)
        #expect(state.hasBaseline)
        #expect(state.announcedRequestIds == [request.id])
    }

    @Test func newRequestAndNewReplyAreAnnouncedOnce() {
        let (_, baseline) = NoteActivityTracker.diff(inbox(), since: NoteActivityState())
        let request = SampleData.noteRequest(direction: .incoming, with: sam)
        let reply = SampleData.noteRequest(direction: .outgoing, with: jo, status: .answered,
                                           reply: .init(text: "Here!", placeLabel: nil, location: nil, respondedAt: .now))
        let now = inbox(incoming: [request], outgoing: [reply])

        let (changes, state) = NoteActivityTracker.diff(now, since: baseline)
        #expect(changes.newRequests == [request])
        #expect(changes.newAnswers == [reply])

        let (again, _) = NoteActivityTracker.diff(now, since: state)
        #expect(again.isEmpty)
    }

    @Test func pendingOutgoingIsNotAnAnswer() {
        let (_, baseline) = NoteActivityTracker.diff(inbox(), since: NoteActivityState())
        let waiting = SampleData.noteRequest(direction: .outgoing, with: jo)
        let (changes, _) = NoteActivityTracker.diff(inbox(outgoing: [waiting]), since: baseline)
        #expect(changes.isEmpty)
    }

    @Test func messages() {
        let request = SampleData.noteRequest(direction: .incoming, with: sam)
        #expect(NoteNotificationMessage.request(request).title == "Sam asked for a note")
        #expect(NoteNotificationMessage.request(request).body == "Let them know where you are. They're also grabbing coffee nearby.")

        let answered = SampleData.noteInbox.outgoing[0]
        let message = NoteNotificationMessage.answer(answered)
        #expect(message.title == "Jo sent you a note")
        #expect(message.body == "Come find me, I saved you a seat · PCL, 3rd floor · 📍 Location shared")

        var declined = SampleData.noteRequest(direction: .outgoing, with: jo)
        declined.status = .declined
        #expect(NoteNotificationMessage.answer(declined).title == "Jo can't share right now")
    }
}

@MainActor
struct NoteRequestMonitorTests {
    @Test func notifiesAboutNewRequestsOnlyAfterBaselineAndOnlyWhenAsked() async throws {
        let api = MockNoteRequestService()
        api.inbox = .empty
        let notifications = MockNotificationService()
        let defaults = UserDefaults(suiteName: "NoteRequestMonitorTests-\(UUID().uuidString)")!
        let monitor = NoteRequestMonitor(account: MockAccountService(), api: api, notifications: notifications, defaults: defaults)

        _ = try await monitor.poll(notify: true)
        api.inbox = SampleData.noteInbox
        _ = try await monitor.poll(notify: false)
        #expect(notifications.posted.isEmpty)

        api.inbox.incoming.append(SampleData.noteRequest(direction: .incoming, with: SampleData.people[3]))
        _ = try await monitor.poll(notify: true)
        #expect(notifications.posted.count == 1)
        #expect(notifications.posted.first?.route == .notes)
        #expect(notifications.posted.first?.title == "Marcus asked for a note")
    }
}

@MainActor
struct NearbyPeopleViewModelTests {
    private func makeViewModel(alertsEnabled: Bool = true) -> (NearbyPeopleViewModel, MockNoteRequestService) {
        let notes = MockNoteRequestService()
        notes.inbox = .empty
        let services = Services.mock().replacing(nearbyAlerts: MockNearbyAlerts(enabled: alertsEnabled),
                                                 noteRequests: notes, noteMonitor: MockNoteRequestMonitor(service: notes))
        return (NearbyPeopleViewModel(user: SampleData.user, services: services), notes)
    }

    @Test func loadsClosestFirstAndSelectsClosestThree() async {
        let (viewModel, _) = makeViewModel()
        await viewModel.load()
        #expect(viewModel.loadState == .loaded)
        #expect(viewModel.people.map(\.distanceMeters) == [200, 400, 600])

        viewModel.selectClosest()
        #expect(viewModel.selection == Set(viewModel.people.prefix(3).map(\.id)))
    }

    @Test func sendingMarksPeopleAskedAndClearsSelection() async {
        let (viewModel, notes) = makeViewModel()
        await viewModel.load()
        let closest = viewModel.people[0]
        viewModel.toggle(closest)
        await viewModel.sendRequests()

        #expect(notes.requestedRecipients == [closest.id])
        #expect(viewModel.isAsked(closest))
        #expect(viewModel.selection.isEmpty)
        #expect(viewModel.confirmation == "Asked Sam. You'll get a notification when they reply.")

        viewModel.toggle(closest)
        #expect(viewModel.selection.isEmpty)
    }

    @Test func alertsOffExplainsInsteadOfLoading() async {
        let (viewModel, _) = makeViewModel(alertsEnabled: false)
        await viewModel.load()
        #expect(viewModel.loadState == .alertsOff)
    }
}

@MainActor
struct NotesInboxViewModelTests {
    private func makeViewModel(location: MockLocationProvider? = nil) -> NotesInboxViewModel {
        let services = Services.mock().replacing(location: location ?? MockLocationProvider())
        return NotesInboxViewModel(user: SampleData.user, services: services)
    }

    @Test func replyWithLocationAnswersTheRequest() async {
        let viewModel = makeViewModel()
        await viewModel.load()
        let request = viewModel.inbox.incoming[0]
        viewModel.startReply(to: request)
        viewModel.draft.text = "  By the fountain  "
        viewModel.draft.placeLabel = "Main Mall"
        viewModel.draft.includeLocation = true

        #expect(await viewModel.sendReply())
        let answered = viewModel.inbox.incoming[0]
        #expect(answered.status == .answered)
        #expect(answered.reply?.text == "By the fountain")
        #expect(answered.reply?.placeLabel == "Main Mall")
        #expect(answered.reply?.location?.latitude == 30.2849)
        #expect(viewModel.replyingTo == nil)
    }

    @Test func replyWithoutLocationSendsNoPosition() async {
        let viewModel = makeViewModel()
        await viewModel.load()
        viewModel.startReply(to: viewModel.inbox.incoming[0])
        viewModel.draft.text = "Library"
        #expect(await viewModel.sendReply())
        #expect(viewModel.inbox.incoming[0].reply?.location == nil)
    }

    @Test func locationUnavailableKeepsSheetOpenWithError() async {
        let location = MockLocationProvider()
        location.lastKnown = nil
        let viewModel = makeViewModel(location: location)
        await viewModel.load()
        viewModel.startReply(to: viewModel.inbox.incoming[0])
        viewModel.draft.text = "Here"
        viewModel.draft.includeLocation = true

        #expect(!(await viewModel.sendReply()))
        #expect(viewModel.replyingTo != nil)
        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.inbox.incoming[0].status == .pending)
    }

    @Test func declining() async {
        let viewModel = makeViewModel()
        await viewModel.load()
        await viewModel.decline(viewModel.inbox.incoming[0])
        #expect(viewModel.inbox.incoming[0].status == .declined)
    }
}

@MainActor
struct NoteRequestContractTests {
    @Test func decodesInbox() throws {
        let json = Data(#"""
        {"incoming":[{"id":"7f1b7c4e-8a0e-4c55-9d0e-0b6c2a1d9f20","direction":"INCOMING",
          "otherUser":{"id":"7f1b7c4e-8a0e-4c55-9d0e-0b6c2a1d9f11","firstName":"Ada","lastName":"L","nickname":null},
          "activity":{"id":"7f1b7c4e-8a0e-4c55-9d0e-0b6c2a1d9f12","name":"Coding","iconId":null,"isCustom":false},
          "status":"PENDING","isExpired":false,"createdAt":"2026-10-25T08:00:00.000Z","expiresAt":"2099-10-25T11:00:00.000Z","reply":null}],
         "outgoing":[{"id":"7f1b7c4e-8a0e-4c55-9d0e-0b6c2a1d9f21","direction":"OUTGOING",
          "otherUser":{"id":"7f1b7c4e-8a0e-4c55-9d0e-0b6c2a1d9f13","firstName":"Bo","lastName":"M","nickname":"B"},
          "activity":null,"status":"ANSWERED","isExpired":false,"createdAt":"2026-10-25T08:00:00.000Z","expiresAt":"2026-10-25T11:00:00.000Z",
          "reply":{"text":"PCL","placeLabel":null,"location":{"latitude":30.2827,"longitude":-97.7381},"respondedAt":"2026-10-25T08:05:00.000Z"}}]}
        """#.utf8)
        let inbox = try JSONDecoder.api.decode(NoteInbox.self, from: json)
        #expect(inbox.incoming.first?.isOpen == true)
        #expect(inbox.openIncomingCount == 1)
        #expect(inbox.outgoing.first?.reply?.location?.longitude == -97.7381)
        #expect(inbox.outgoing.first?.otherUser.displayName == "B")
    }

    @Test func nearbyUsersCarryDistance() throws {
        let json = Data(#"{"activity":null,"radiusMeters":1600,"users":[{"id":"7f1b7c4e-8a0e-4c55-9d0e-0b6c2a1d9f11","firstName":"Ada","lastName":"L","nickname":null,"status":null,"distanceMeters":300}]}"#.utf8)
        #expect(try JSONDecoder.api.decode(NearbyResult.self, from: json).users.first?.distanceMeters == 300)
    }

    @Test func routes() throws {
        let userId = UUID(uuidString: "7F1B7C4E-8A0E-4C55-9D0E-0B6C2A1D9F11")!
        let requestId = UUID(uuidString: "7F1B7C4E-8A0E-4C55-9D0E-0B6C2A1D9F20")!
        #expect(Endpoint.noteRequests(for: userId).path == "users/7f1b7c4e-8a0e-4c55-9d0e-0b6c2a1d9f11/note-requests")
        let reply = try Endpoint.replyToNoteRequest(requestId, reply: NoteReplyRequest(text: "hi"), for: userId)
        #expect(reply.method == .post)
        #expect(reply.path == "users/7f1b7c4e-8a0e-4c55-9d0e-0b6c2a1d9f11/note-requests/7f1b7c4e-8a0e-4c55-9d0e-0b6c2a1d9f20/reply")
        #expect(Endpoint.declineNoteRequest(requestId, for: userId).path.hasSuffix("/decline"))
        let body = try #require(try JSONSerialization.jsonObject(with: reply.body ?? Data()) as? [String: Any])
        #expect(Set(body.keys) == ["text"])
    }

    @Test func distanceText() {
        #expect(DistanceText.approximate(300).hasPrefix("~"))
    }
}

extension Services {
    /// A copy with some services swapped, so tests don't break each time `Services` gains a field.
    func replacing(
        nearbyAlerts: NearbyAlerting? = nil,
        push: PushRegistering? = nil,
        noteRequests: NoteRequestServicing? = nil,
        noteMonitor: NoteRequestMonitoring? = nil,
        location: LocationProviding? = nil
    ) -> Services {
        Services(
            account: account, activities: activities, friends: friends, calendar: calendar,
            statusPreferences: statusPreferences, statuses: statuses, people: people,
            nearbyAlerts: nearbyAlerts ?? self.nearbyAlerts,
            push: push ?? self.push,
            noteRequests: noteRequests ?? self.noteRequests,
            noteMonitor: noteMonitor ?? self.noteMonitor,
            location: location ?? self.location,
            router: router, widgets: widgets
        )
    }
}

@MainActor
struct ActivitiesPageTests {
    private let activities = MockActivityService()

    private func makeViewModel() async -> HomeViewModel {
        let viewModel = HomeViewModel(user: SampleData.user, services: Services.mock().replacingActivities(activities))
        await viewModel.load()
        return viewModel
    }

    @Test func yourListAndTheRestAreSeparate() async {
        activities.standardActivities.append(StandardActivity(name: "Stargazing", defaultDurationMinutes: 60))
        let viewModel = await makeViewModel()

        // The mock saves the first five at sign-up.
        #expect(viewModel.myList.map(\.name) == SampleData.activities.prefix(5).map(\.name))
        let addable = viewModel.addableChoices.map(\.name)
        #expect(addable == SampleData.activities.dropFirst(5).map(\.name) + ["Stargazing"])
        #expect(Set(addable).isDisjoint(with: viewModel.myList.map(\.name)))
    }

    @Test func addingAStandardActivityMovesItIntoYourList() async throws {
        activities.standardActivities.append(StandardActivity(name: "Stargazing", defaultDurationMinutes: 60))
        let viewModel = await makeViewModel()
        let stargazing = try #require(viewModel.addableChoices.first { $0.name == "Stargazing" })

        #expect(await viewModel.addToMyList(stargazing))
        #expect(activities.savedStandardNames.contains("Stargazing"))
        #expect(viewModel.myList.contains { $0.name == "Stargazing" && !$0.isCustom })
        #expect(!viewModel.addableChoices.contains { $0.name == "Stargazing" })
        // Its new row is usable for a status.
        #expect(viewModel.activities.contains { $0.name == "Stargazing" })
    }

    @Test func addingYourOwnCustomActivity() async throws {
        let mine = Activity(id: UUID(), ownerId: SampleData.user.id, name: "Robotics club", iconId: nil, defaultDurationMinutes: 90, isCustom: true)
        activities.activities.insert(mine, at: 0)
        let viewModel = await makeViewModel()
        let choice = try #require(viewModel.addableChoices.first)
        #expect(choice.customId == mine.id)

        #expect(await viewModel.addToMyList(choice))
        #expect(viewModel.myList.contains(mine))
        #expect(activities.savedIds.contains(mine.id))
    }

    @Test func removingTakesItOutButKeepsDefaultsAndAtLeastOne() async throws {
        let viewModel = await makeViewModel()
        let first = try #require(viewModel.myList.first)
        viewModel.draft.activity = first

        await viewModel.removeFromMyList(first)
        #expect(!viewModel.myList.contains(first))
        #expect(viewModel.addableChoices.contains { $0.name == first.name })
        #expect(viewModel.draft.activity == nil)

        let free = Activity(id: UUID(), ownerId: SampleData.user.id, name: "Free", iconId: nil, defaultDurationMinutes: 60, isCustom: true)
        #expect(!viewModel.canRemoveFromMyList(free))
    }

    @Test func newCustomActivityIsAddedAndDrafted() async {
        let viewModel = await makeViewModel()
        await viewModel.createAndAddActivity(name: "Hackathon judging", durationMinutes: 45)

        #expect(viewModel.myList.contains { $0.name == "Hackathon judging" && $0.isCustom })
        #expect(viewModel.draft.activity?.name == "Hackathon judging")
    }
}

extension Services {
    func replacingActivities(_ activities: ActivityServicing) -> Services {
        Services(
            account: account, activities: activities, friends: friends, calendar: calendar,
            statusPreferences: statusPreferences, statuses: statuses, people: people,
            nearbyAlerts: nearbyAlerts, push: push, noteRequests: noteRequests, noteMonitor: noteMonitor,
            location: location, router: router, widgets: widgets
        )
    }
}
