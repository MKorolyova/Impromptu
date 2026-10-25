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

    func isEmailRegistered(_ email: String) async throws -> Bool {
        email.caseInsensitiveCompare(user.email) == .orderedSame
    }

    func updateProfile(_ request: UpdateUserRequest, for userId: UUID) async throws -> User {
        user.firstName = request.firstName
        user.lastName = request.lastName
        user.nickname = request.nickname
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
    var savedIds: [UUID] = Array(SampleData.activities.prefix(5).map(\.id))
    var standardActivities = SampleData.activities.map { StandardActivity(name: $0.name, defaultDurationMinutes: $0.defaultDurationMinutes) }
    /// Standard names in the last save, before they were turned into rows.
    private(set) var savedStandardNames: [String] = []

    func fetchStandardActivities() async throws -> [StandardActivity] {
        standardActivities
    }

    func fetchActivities(for userId: UUID) async throws -> [Activity] {
        activities
    }

    /// Like the server: a standard activity's row is reused, or made the first time it's saved.
    private func standardRow(named name: String) throws -> Activity {
        if let row = activities.first(where: { !$0.isCustom && $0.name == name }) { return row }
        guard let standard = standardActivities.first(where: { $0.name == name }) else {
            throw APIError.http(statusCode: 404, code: .notFound, message: "Not a standard activity")
        }
        let row = Activity(id: UUID(), ownerId: nil, name: name, iconId: nil,
                           defaultDurationMinutes: standard.defaultDurationMinutes, isCustom: false)
        activities.append(row)
        return row
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

    func fetchSavedActivities(for userId: UUID) async throws -> [Activity] {
        activities.filter { savedIds.contains($0.id) }
    }

    func saveActivities(customIds: [UUID], standardNames: [String], for userId: UUID) async throws -> [Activity] {
        savedStandardNames = standardNames
        let standardIds = try standardNames.map { try standardRow(named: $0).id }
        savedIds = customIds + standardIds
        return try await fetchSavedActivities(for: userId)
    }
}

final class MockFriendService: FriendServicing {
    var friends: [Friend] = [
        Friend(id: SampleData.people[0].id, firstName: "Sam", lastName: "Lee", nickname: nil, canSeeLocation: true, canSeeNotes: true),
        Friend(id: SampleData.people[1].id, firstName: "Jordan", lastName: "Park", nickname: "Jo", canSeeLocation: false, canSeeNotes: true),
    ]
    /// Emails `addFriend` recognizes.
    var directory: [String: Friend] = [
        "priya@example.com": Friend(id: SampleData.people[2].id, firstName: "Priya", lastName: "Shah", nickname: nil,
                                    canSeeLocation: false, canSeeNotes: false),
    ]

    func fetchFriends(for userId: UUID) async throws -> [Friend] { friends }

    func addFriend(email: String, access: FriendAccess, for userId: UUID) async throws -> Friend {
        guard var friend = directory[email.lowercased()] else {
            throw APIError.http(statusCode: 404, code: .notFound, message: "No one on Impromptu uses that email")
        }
        if let existing = friends.first(where: { $0.id == friend.id }) { friend = existing }
        friend.apply(access)
        upsert(friend)
        return friend
    }

    func updateFriend(_ friendId: UUID, access: FriendAccess, for userId: UUID) async throws -> Friend {
        guard var friend = friends.first(where: { $0.id == friendId }) else {
            throw APIError.http(statusCode: 404, code: .notFound, message: "Friend not found")
        }
        friend.apply(access)
        upsert(friend)
        return friend
    }

    func removeFriend(_ friendId: UUID, for userId: UUID) async throws {
        friends.removeAll { $0.id == friendId }
    }

    private func upsert(_ friend: Friend) {
        if let index = friends.firstIndex(where: { $0.id == friend.id }) {
            friends[index] = friend
        } else {
            friends.append(friend)
        }
    }
}

private extension Friend {
    mutating func apply(_ access: FriendAccess) {
        if let canSeeLocation = access.canSeeLocation { self.canSeeLocation = canSeeLocation }
        if let canSeeNotes = access.canSeeNotes { self.canSeeNotes = canSeeNotes }
    }
}

final class MockCalendarService: CalendarServicing {
    var isConnected = false

    func isGoogleCalendarConnected(for userId: UUID) async throws -> Bool { isConnected }

    func startGoogleCalendarConnection(for userId: UUID) async throws -> CalendarConnection {
        CalendarConnection(authURL: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!, callbackScheme: "impromptu")
    }
}

final class MockStatusPreferencesStore: StatusPreferencesStoring {
    private(set) var saved: [UUID: Set<StatusSource>] = [:]

    func sources(for userId: UUID) -> Set<StatusSource> { saved[userId] ?? [.manual] }
    func save(_ sources: Set<StatusSource>, for userId: UUID) { saved[userId] = sources }
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

/// Records every request and answers each with an empty success; for services whose requests are the point.
final class RecordingAPIClient: APIClient {
    private(set) var sent: [Endpoint] = []

    func send<Response: Decodable>(_ endpoint: Endpoint) async throws -> Response {
        sent.append(endpoint)
        throw APIError.http(statusCode: 500, code: nil, message: "RecordingAPIClient has no responses")
    }

    func send(_ endpoint: Endpoint) async throws {
        sent.append(endpoint)
    }
}

final class MockPushService: PushRegistering {
    private(set) var registerCount = 0
    private(set) var receivedTokens: [Data] = []
    private(set) var unregisteredUserIds: [UUID] = []

    func register() { registerCount += 1 }
    func didReceiveDeviceToken(_ deviceToken: Data) async { receivedTokens.append(deviceToken) }
    func unregister(userId: UUID) async { unregisteredUserIds.append(userId) }
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

    private(set) var appearanceReloads = 0

    func reloadAppearance() {
        appearanceReloads += 1
    }
}
