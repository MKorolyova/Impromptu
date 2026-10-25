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
            statuses: statuses ?? MockStatusService(),
            people: people ?? MockPeopleService(),
            nearbyAlerts: nearbyAlerts ?? MockNearbyAlerts(enabled: false),
            widgets: widgets
        )
        return HomeViewModel(user: SampleData.user, services: services)
    }

    @Test func nearbyLoadsWhenEnabledAndClearsWhenTurnedOff() async {
        let viewModel = makeViewModel(nearbyAlerts: MockNearbyAlerts(enabled: true))
        await viewModel.load()
        #expect(viewModel.nearby?.users.count == 2)

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

    @Test func publishingDraftSetsStatusAndClosesDropDown() async {
        let viewModel = makeViewModel(statuses: MockStatusService(status: nil))
        await viewModel.load()
        viewModel.toggleComposer()
        #expect(viewModel.isComposerOpen)
        #expect(!viewModel.canPublishDraft)

        let activity = SampleData.activities[0]
        viewModel.draft.activity = activity
        viewModel.draft.note = "  Hi  "
        viewModel.draft.durationMinutes = 30
        await viewModel.publishDraft()

        #expect(viewModel.myStatus?.activity.id == activity.id)
        #expect(viewModel.myStatus?.note == "Hi")
        let length = viewModel.myStatus.map { $0.expiresAt.timeIntervalSince($0.startedAt) } ?? 0
        #expect(abs(length - 30 * 60) < 0.001)
        #expect(!viewModel.isComposerOpen)
        #expect(widgets.lastStatus?.note == "Hi")

        await viewModel.clearStatus()
        #expect(viewModel.myStatus == nil)
        #expect(widgets.lastStatus == nil)
    }

    @Test func openingDropDownStartsFromCurrentStatus() async {
        let viewModel = makeViewModel()
        await viewModel.load()
        viewModel.toggleComposer()

        #expect(viewModel.draft.activity?.id == viewModel.myStatus?.activity.id)
        #expect(viewModel.draft.note == viewModel.myStatus?.note)
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
        #expect(try JSONDecoder.api.decode(UserEnvelope.self, from: json).user.displayName == "Ada")
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

    @Test func newUserWithinTheHourWaitsThenNotifies() {
        let (_, first) = NearbyAlertPolicy.evaluate(state: .init(), activityId: coding, matchingUserIds: [sam], now: start)

        let (early, waiting) = NearbyAlertPolicy.evaluate(state: first, activityId: coding, matchingUserIds: [sam, jo],
                                                          now: start.addingTimeInterval(20 * 60))
        #expect(early == .skip(.tooSoon))
        #expect(!waiting.announcedUserIds.contains(jo))

        let (later, _) = NearbyAlertPolicy.evaluate(state: waiting, activityId: coding, matchingUserIds: [sam, jo],
                                                    now: start.addingTimeInterval(61 * 60))
        #expect(later == .notify(newUserIds: [jo]))
    }

    @Test func changingActivityStartsOverButKeepsHourlyLimit() {
        let (_, first) = NearbyAlertPolicy.evaluate(state: .init(), activityId: coding, matchingUserIds: [sam], now: start)
        let studying = UUID()

        let (soon, rebased) = NearbyAlertPolicy.evaluate(state: first, activityId: studying, matchingUserIds: [sam],
                                                         now: start.addingTimeInterval(10 * 60))
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

    @Test func peopleSeenInTheAppAreNotAnnounced() {
        let seen = NearbyAlertPolicy.markSeen(state: .init(), activityId: coding, userIds: [sam, jo])
        let (decision, _) = NearbyAlertPolicy.evaluate(state: seen, activityId: coding, matchingUserIds: [sam, jo, priya], now: start)
        #expect(decision == .notify(newUserIds: [priya]))
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
        #expect(message.body == "Sam is also grabbing coffee within a mile.")
    }

    @Test func severalPeopleWithOthersAlreadyAnnounced() {
        let message = NearbyAlertMessage(newPeople: ["Sam", "Jo", "Priya"].map(person), totalCount: 5, activityName: "Coding")
        #expect(message.title == "3 new people nearby")
        #expect(message.body == "Sam, Jo and 1 more are also coding within a mile. 5 people nearby in all.")
    }
}

@MainActor
struct NearbyAlertsServiceTests {
    private let api = MockNearbyService()
    private let location = MockLocationProvider()
    private let notifications = MockNotificationService()
    private let defaults = UserDefaults(suiteName: "NearbyAlertsServiceTests-\(UUID().uuidString)")!

    private func makeService(now: @escaping () -> Date = { .now }) -> NearbyAlertsService {
        NearbyAlertsService(account: MockAccountService(), api: api, location: location,
                            notifications: notifications, defaults: defaults, now: now)
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

    @Test func backgroundCheckSharesLocationAndNotifiesOnlyOnceForSamePeople() async {
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let service = makeService(now: { clock })
        _ = await service.enable()

        await service.performBackgroundCheck()
        #expect(api.sharedLocations.count == 1)
        #expect(notifications.posted.count == 1)

        clock.addTimeInterval(2 * 3600)
        await service.performBackgroundCheck()
        #expect(notifications.posted.count == 1)
    }

    @Test func peopleSeenInForegroundDontTriggerNotification() async throws {
        let service = makeService()
        _ = await service.enable()

        let result = try await service.refreshInForeground()
        #expect(result.users.count == 2)

        await service.performBackgroundCheck()
        #expect(notifications.posted.isEmpty)
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
        #expect(Endpoint.nearby(for: userId, radiusMeters: 1600).queryItems == [URLQueryItem(name: "radiusMeters", value: "1600")])
        #expect(Endpoint.people.path == "feed")
    }
}
