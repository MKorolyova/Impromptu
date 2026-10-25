//
//  MockServices.swift
//  Impromptu-app
//
//  In-memory implementations for previews and tests. No network.
//

import Foundation

final class MockAccountService: AccountServicing {
    static let password = "password"

    var user = SampleData.user
    private(set) var storedUserId: UUID?

    init(signedIn: Bool = true) {
        storedUserId = signedIn ? user.id : nil
    }

    /// Accepts the sample user's email with `MockAccountService.password`.
    func logIn(email: String, password: String) async throws -> User {
        guard email.caseInsensitiveCompare(user.email) == .orderedSame, password == Self.password else {
            throw APIError.http(statusCode: 401, code: .unauthorized, message: "Invalid email or password")
        }
        storedUserId = user.id
        return user
    }

    func createAccount(_ request: CreateUserRequest) async throws -> User {
        user = User(id: UUID(), email: request.email, firstName: request.firstName,
                    lastName: request.lastName, nickname: request.nickname, timezone: request.timezone)
        storedUserId = user.id
        return user
    }

    func restoreUser(_ userId: UUID) async throws -> User {
        guard userId == user.id else { throw APIError.http(statusCode: 404, code: .notFound, message: "User not found") }
        return user
    }

    func signOut() {
        storedUserId = nil
    }

    func deleteAccount(_ userId: UUID) async throws {
        signOut()
    }
}

final class MockActivityService: ActivityServicing {
    var activities = SampleData.activities

    func fetchActivities(for userId: UUID) async throws -> [Activity] {
        activities
    }

    func createActivity(name: String, durationMinutes: Int, for userId: UUID) async throws -> Activity {
        let activity = Activity(id: UUID(), ownerId: userId, name: name, iconId: nil,
                                defaultDurationMinutes: durationMinutes, isCustom: true)
        activities.insert(activity, at: 0)
        return activity
    }

    func deleteActivity(_ activity: Activity, for userId: UUID) async throws {
        activities.removeAll { $0.id == activity.id }
    }
}

final class MockStatusService: StatusServicing {
    var status: Status?

    init(status: Status? = SampleData.status(for: SampleData.user.id, activity: SampleData.activities[3], note: "HackTX")) {
        self.status = status
    }

    func currentStatus(for userId: UUID) async throws -> Status? {
        status
    }

    func setStatus(activity: Activity, note: String?, duration: TimeInterval?, for userId: UUID) async throws -> Status {
        var newStatus = SampleData.status(for: userId, activity: activity, note: note)
        if let duration {
            newStatus.expiresAt = newStatus.startedAt.addingTimeInterval(duration)
        }
        status = newStatus
        return newStatus
    }

    func clearStatus(_ status: Status) async throws {
        self.status = nil
    }
}

final class MockPeopleService: PeopleServicing {
    var people = SampleData.people

    func fetchPeople() async throws -> [Person] {
        people
    }
}

final class MockNearbyService: NearbyServicing {
    var result = NearbyResult(activity: SampleData.activities[3].summary, radiusMeters: NearbyAlertsService.radiusMeters,
                              users: SampleData.people.prefix(3).enumerated().map { index, person in
                                  var nearby = person
                                  nearby.distanceMeters = (index + 1) * 200
                                  return nearby
                              })
    private(set) var sharedLocations: [Coordinate] = []
    private(set) var stopSharingCount = 0

    func shareLocation(_ coordinate: Coordinate, for userId: UUID) async throws {
        sharedLocations.append(coordinate)
    }

    func stopSharing(for userId: UUID) async throws {
        stopSharingCount += 1
    }

    func fetchNearby(for userId: UUID, radiusMeters: Int) async throws -> NearbyResult {
        result
    }
}

final class MockLocationProvider: LocationProviding {
    var authorization: LocationAuthorization
    var lastKnown: Coordinate? = Coordinate(latitude: 30.2849, longitude: -97.7341)
    var onUpdate: ((Coordinate) -> Void)?
    private(set) var isMonitoring = false

    init(authorization: LocationAuthorization = .always) {
        self.authorization = authorization
    }

    func requestAuthorization() async -> LocationAuthorization { authorization }
    func startMonitoring() { isMonitoring = true }
    func stopMonitoring() { isMonitoring = false }
    func currentLocation() async -> Coordinate? { lastKnown }
}

final class MockNotificationService: NotificationPosting {
    var authorized = true
    private(set) var posted: [(title: String, body: String, route: AppRoute)] = []

    func requestAuthorization() async -> Bool { authorized }
    func isAuthorized() async -> Bool { authorized }
    func post(id: String, title: String, body: String, route: AppRoute) async { posted.append((title, body, route)) }
}

/// For previews: alerts already on, with two matches.
final class MockNearbyAlerts: NearbyAlerting {
    var isEnabled: Bool
    var locationAuthorization: LocationAuthorization = .always
    var result = MockNearbyService().result

    init(enabled: Bool = true) {
        isEnabled = enabled
    }

    func enable() async -> NearbyEnableOutcome {
        isEnabled = true
        return NearbyEnableOutcome(location: locationAuthorization, notificationsAllowed: true)
    }

    func disable(userId: UUID?) async { isEnabled = false }
    func resume() {}
    func refreshInForeground() async throws -> NearbyResult { isEnabled ? result : .empty }
    func performBackgroundCheck() async {}
}

final class MockNoteRequestService: NoteRequestServicing {
    var inbox = SampleData.noteInbox
    private(set) var requestedRecipients: [UUID] = []

    func fetchInbox(for userId: UUID) async throws -> NoteInbox { inbox }

    func requestNotes(from recipientIds: [UUID], for userId: UUID) async throws -> CreateNoteRequestsResponse {
        requestedRecipients += recipientIds
        let created = recipientIds.compactMap { id in SampleData.people.first { $0.id == id } }
            .map { SampleData.noteRequest(direction: .outgoing, with: $0, minutesAgo: 0) }
        inbox.outgoing.insert(contentsOf: created, at: 0)
        return CreateNoteRequestsResponse(requests: created, skippedRecipientIds: [])
    }

    func reply(to request: NoteRequest, text: String, placeLabel: String?, location: Coordinate?, for userId: UUID) async throws -> NoteRequest {
        var answered = request
        answered.status = .answered
        answered.reply = NoteRequest.Reply(text: text, placeLabel: placeLabel,
                                           location: location.map { .init(latitude: $0.latitude, longitude: $0.longitude) },
                                           respondedAt: .now)
        replace(answered)
        return answered
    }

    func decline(_ request: NoteRequest, for userId: UUID) async throws -> NoteRequest {
        var declined = request
        declined.status = .declined
        replace(declined)
        return declined
    }

    private func replace(_ request: NoteRequest) {
        if let index = inbox.incoming.firstIndex(where: { $0.id == request.id }) { inbox.incoming[index] = request }
    }
}

final class MockNoteRequestMonitor: NoteRequestMonitoring {
    let service: MockNoteRequestService
    private(set) var pollCount = 0

    init(service: MockNoteRequestService = MockNoteRequestService()) {
        self.service = service
    }

    func poll(notify: Bool) async throws -> NoteInbox {
        pollCount += 1
        return service.inbox
    }

    func reset() {}
}

final class MockWidgetSyncService: WidgetSyncing {
    private(set) var syncCount = 0
    private(set) var lastPeople: [Person] = []
    private(set) var lastStatus: Status?

    func sync(user: User?, myStatus: Status?, people: [Person]) {
        syncCount += 1
        lastStatus = myStatus
        lastPeople = people
    }

    func clear() {
        lastStatus = nil
        lastPeople = []
    }
}
