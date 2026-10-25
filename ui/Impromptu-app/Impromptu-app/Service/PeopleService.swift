//
//  PeopleService.swift
//  Impromptu-app
//

import Foundation

protocol PeopleServicing {
    /// Everyone on Impromptu with their current status, people with a status first.
    func fetchPeople() async throws -> [Person]
}

private struct PeopleEnvelope: Decodable {
    var users: [Person]
}

final class PeopleService: PeopleServicing {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func fetchPeople() async throws -> [Person] {
        let envelope: PeopleEnvelope = try await client.send(.people)
        return envelope.users
    }
}
