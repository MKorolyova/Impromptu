//
//  CalendarService.swift
//  Impromptu-app
//

import Foundation

/// Where to send the user to approve Google Calendar access, and the scheme the API returns to
/// (`impromptu://google-calendar?result=connected|denied|expired|failed`).
struct CalendarConnection: Equatable {
    var authURL: URL
    var callbackScheme: String
}

protocol CalendarServicing {
    func isGoogleCalendarConnected(for userId: UUID) async throws -> Bool
    /// The returned link is valid for 10 minutes.
    func startGoogleCalendarConnection(for userId: UUID) async throws -> CalendarConnection
}

private struct GoogleCalendarEnvelope: Decodable {
    struct State: Decodable {
        var connected: Bool
    }

    var googleCalendar: State
}

private struct ConnectEnvelope: Decodable {
    var authUrl: URL
}

final class CalendarService: CalendarServicing {
    private let client: APIClient
    private let callbackScheme: String

    init(client: APIClient, callbackScheme: String = APIConfig.calendarCallbackScheme) {
        self.client = client
        self.callbackScheme = callbackScheme
    }

    func isGoogleCalendarConnected(for userId: UUID) async throws -> Bool {
        let envelope: GoogleCalendarEnvelope = try await client.send(.googleCalendar(for: userId))
        return envelope.googleCalendar.connected
    }

    func startGoogleCalendarConnection(for userId: UUID) async throws -> CalendarConnection {
        let envelope: ConnectEnvelope = try await client.send(.connectGoogleCalendar(for: userId))
        return CalendarConnection(authURL: envelope.authUrl, callbackScheme: callbackScheme)
    }
}
