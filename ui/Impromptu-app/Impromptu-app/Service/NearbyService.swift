//
//  NearbyService.swift
//  Impromptu-app
//

import Foundation

protocol NearbyServicing {
    func shareLocation(_ coordinate: Coordinate, for userId: UUID) async throws
    /// Removes your position from the server so you stop appearing nearby.
    func stopSharing(for userId: UUID) async throws
    func fetchNearby(for userId: UUID, radiusMeters: Int) async throws -> NearbyResult
}

final class NearbyService: NearbyServicing {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func shareLocation(_ coordinate: Coordinate, for userId: UUID) async throws {
        let request = UpdateLocationRequest(latitude: coordinate.latitude, longitude: coordinate.longitude, accuracyMeters: coordinate.accuracy)
        try await client.send(.updateLocation(request, for: userId))
    }

    func stopSharing(for userId: UUID) async throws {
        try await client.send(.deleteLocation(for: userId))
    }

    func fetchNearby(for userId: UUID, radiusMeters: Int) async throws -> NearbyResult {
        try await client.send(.nearby(for: userId, radiusMeters: radiusMeters))
    }
}
