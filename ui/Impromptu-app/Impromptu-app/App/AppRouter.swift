//
//  AppRouter.swift
//  Impromptu-app
//

import Foundation
import Observation

/// Screens a notification can open.
enum AppRoute: String, Equatable {
    /// People nearby doing the same thing, to ask for a note.
    case nearbyPeople
    /// Note requests and replies.
    case notes
}

/// Where the app has been asked to go, e.g. by tapping a notification. The home screen opens the
/// route and clears it. Held here because a tap can arrive before the home screen exists.
@Observable
final class AppRouter {
    var pendingRoute: AppRoute?
}
