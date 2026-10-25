//
//  Person.swift
//  Impromptu-app
//

import Foundation

/// `UserWithStatus` in api/openapi.yaml: someone's public profile and current status.
struct Person: Codable, Identifiable, Hashable {
    let id: UUID
    var firstName: String
    var lastName: String
    var nickname: String?
    var status: Status?

    var displayName: String {
        nickname ?? firstName
    }

    var fullName: String {
        "\(firstName) \(lastName)"
    }

    var activeStatus: Status? {
        status.flatMap { $0.isActive() ? $0 : nil }
    }
}
