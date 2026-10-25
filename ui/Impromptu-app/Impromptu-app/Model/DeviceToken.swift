//
//  DeviceToken.swift
//  Impromptu-app
//

import Foundation

/// Body of `POST /users/{userId}/device-tokens`.
struct SaveDeviceTokenRequest: Encodable {
    /// The APNs device token, hex-encoded.
    var token: String
    var environment: PushEnvironment
}

/// Body of `DELETE /users/{userId}/device-tokens`.
struct DeleteDeviceTokenRequest: Encodable {
    var token: String
}

/// Which APNs server the token belongs to. Builds run from Xcode get sandbox tokens; the server
/// corrects this if it guessed wrong.
enum PushEnvironment: String, Encodable {
    case sandbox = "SANDBOX"
    case production = "PRODUCTION"

    static var current: PushEnvironment {
        #if DEBUG
        .sandbox
        #else
        .production
        #endif
    }
}
