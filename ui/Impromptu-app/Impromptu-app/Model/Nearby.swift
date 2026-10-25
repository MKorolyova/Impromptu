//
//  Nearby.swift
//  Impromptu-app
//

import CoreLocation
import Foundation

/// A position to report to the server. Kept free of CoreLocation so services and tests stay simple.
nonisolated struct Coordinate: Equatable, Sendable {
    var latitude: Double
    var longitude: Double
    /// Horizontal accuracy in meters, if known.
    var accuracy: Double?

    init(latitude: Double, longitude: Double, accuracy: Double? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.accuracy = accuracy
    }

    init(_ location: CLLocation) {
        self.init(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            accuracy: location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil
        )
    }
}

/// Body of `PUT /users/{userId}/location`.
struct UpdateLocationRequest: Encodable {
    var latitude: Double
    var longitude: Double
    var accuracyMeters: Double?
}

/// Response of `GET /users/{userId}/nearby`: people within the radius doing the same activity as you.
struct NearbyResult: Decodable, Equatable {
    /// Your current activity; nil when you have no active status.
    var activity: ActivitySummary?
    var radiusMeters: Int
    var users: [Person]

    static let empty = NearbyResult(activity: nil, radiusMeters: 0, users: [])
}
