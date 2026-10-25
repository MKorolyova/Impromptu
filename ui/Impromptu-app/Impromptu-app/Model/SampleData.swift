//
//  SampleData.swift
//  Impromptu-app
//
//  Fixtures for previews, mock services and tests.
//

import Foundation

enum SampleData {
    static let user = User(
        id: UUID(),
        email: "alex@example.com",
        firstName: "Alex",
        lastName: "Rivera",
        nickname: nil,
        timezone: "America/Chicago"
    )

    static let activities: [Activity] = [
        ("Working", 120), ("Grabbing coffee", 30), ("Studying", 90),
        ("Coding", 120), ("Working out", 60), ("Hanging out", 120),
        ("Eating out", 90), ("Gaming", 120), ("Napping", 30),
    ].map { Activity(id: UUID(), ownerId: nil, name: $0.0, iconId: nil, defaultDurationMinutes: $0.1, isCustom: false) }

    static func status(for userId: UUID, activity: Activity, note: String? = nil, startedAt: Date = .now) -> Status {
        Status(
            id: UUID(),
            userId: userId,
            activity: activity.summary,
            note: note,
            source: .manual,
            startedAt: startedAt,
            expiresAt: startedAt.addingTimeInterval(activity.defaultDuration)
        )
    }

    static let people: [Person] = {
        func person(_ first: String, _ last: String, nickname: String? = nil,
                    activity: Int? = nil, note: String? = nil, minutesAgo: Double = 0) -> Person {
            let id = UUID()
            let status = activity.map {
                SampleData.status(for: id, activity: activities[$0], note: note,
                                  startedAt: .now.addingTimeInterval(-minutesAgo * 60))
            }
            return Person(id: id, firstName: first, lastName: last, nickname: nickname, status: status)
        }
        return [
            person("Sam", "Lee", activity: 1, note: "Anyone want to join? ☕️", minutesAgo: 4),
            person("Jordan", "Park", nickname: "Jo", activity: 2, note: "Library 3F, quiet zone", minutesAgo: 25),
            person("Priya", "Shah", activity: 7, minutesAgo: 40),
            person("Marcus", "Bell", activity: 4, note: "Leg day 😩", minutesAgo: 52),
            person("Taylor", "Kim"),
            person("Diego", "Ramos"),
        ]
    }()
}

extension SampleData {
    static func noteRequest(
        direction: NoteRequest.Direction,
        with person: Person,
        status: NoteRequest.State = .pending,
        reply: NoteRequest.Reply? = nil,
        minutesAgo: Double = 5
    ) -> NoteRequest {
        let created = Date.now.addingTimeInterval(-minutesAgo * 60)
        return NoteRequest(
            id: UUID(),
            direction: direction,
            otherUser: UserProfile(id: person.id, firstName: person.firstName, lastName: person.lastName, nickname: person.nickname),
            activity: person.status?.activity,
            status: status,
            isExpired: false,
            createdAt: created,
            expiresAt: created.addingTimeInterval(3 * 3600),
            reply: reply
        )
    }

    static let noteInbox = NoteInbox(
        incoming: [noteRequest(direction: .incoming, with: people[0], minutesAgo: 2)],
        outgoing: [
            noteRequest(direction: .outgoing, with: people[1], status: .answered, reply: NoteRequest.Reply(
                text: "Come find me, I saved you a seat", placeLabel: "PCL, 3rd floor",
                location: NoteRequest.ReplyLocation(latitude: 30.2827, longitude: -97.7381), respondedAt: .now.addingTimeInterval(-60))),
            noteRequest(direction: .outgoing, with: people[2], minutesAgo: 10),
        ]
    )
}
