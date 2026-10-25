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
        #expect(result.users.count == 3)

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
        var services = Services.mock()
        services = Services(account: services.account, activities: services.activities, statuses: services.statuses,
                            people: services.people, nearbyAlerts: MockNearbyAlerts(enabled: alertsEnabled),
                            noteRequests: notes, noteMonitor: MockNoteRequestMonitor(service: notes),
                            location: services.location, router: services.router, widgets: services.widgets)
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
        let base = Services.mock()
        let services = Services(account: base.account, activities: base.activities, statuses: base.statuses, people: base.people,
                                nearbyAlerts: base.nearbyAlerts, noteRequests: base.noteRequests, noteMonitor: base.noteMonitor,
                                location: location ?? MockLocationProvider(), router: base.router, widgets: base.widgets)
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
