//
//  LocationProvider.swift
//  Impromptu-app
//

import CoreLocation
import Foundation

enum LocationAuthorization: Equatable {
    case notDetermined
    case denied
    /// Works in the app, but iOS won't wake it in the background.
    case whileUsing
    case always
}

protocol LocationProviding: AnyObject {
    var authorization: LocationAuthorization { get }
    /// The most recent fix iOS has, if any.
    var lastKnown: Coordinate? { get }
    /// Called on the main actor for each significant-change fix (not for `currentLocation()`).
    var onUpdate: ((Coordinate) -> Void)? { get set }
    /// Asks for Always access; resolves once the user has answered the first prompt.
    func requestAuthorization() async -> LocationAuthorization
    /// Significant-change monitoring: roughly every 500 m, and it relaunches the app if needed.
    func startMonitoring()
    func stopMonitoring()
    /// A fresh fix, or the last known one if none arrives within a few seconds.
    func currentLocation() async -> Coordinate?
}

final class CoreLocationProvider: NSObject, LocationProviding, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var authorizationWaiters: [CheckedContinuation<LocationAuthorization, Never>] = []
    private var fixWaiters: [CheckedContinuation<Coordinate?, Never>] = []
    private static let fixTimeout: Duration = .seconds(10)
    var onUpdate: ((Coordinate) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        // Nearby is 3 miles; a coarse fix is enough and saves battery.
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var authorization: LocationAuthorization {
        switch manager.authorizationStatus {
        case .notDetermined: .notDetermined
        case .authorizedAlways: .always
        case .authorizedWhenInUse: .whileUsing
        default: .denied
        }
    }

    var lastKnown: Coordinate? {
        manager.location.map(Coordinate.init)
    }

    func requestAuthorization() async -> LocationAuthorization {
        switch authorization {
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                authorizationWaiters.append(continuation)
                manager.requestAlwaysAuthorization()
            }
        case .whileUsing:
            // iOS shows the upgrade prompt at most once and may not call back, so don't wait on it.
            manager.requestAlwaysAuthorization()
            return .whileUsing
        case .denied, .always:
            return authorization
        }
    }

    func startMonitoring() {
        manager.startMonitoringSignificantLocationChanges()
    }

    func stopMonitoring() {
        manager.stopMonitoringSignificantLocationChanges()
    }

    func currentLocation() async -> Coordinate? {
        guard authorization == .always || authorization == .whileUsing else { return nil }
        return await withCheckedContinuation { continuation in
            fixWaiters.append(continuation)
            manager.requestLocation()
            // Don't leave a background check hanging if no fix arrives.
            Task {
                try? await Task.sleep(for: Self.fixTimeout)
                resolveFixWaiters(with: lastKnown)
            }
        }
    }

    private func resolveFixWaiters(with coordinate: Coordinate?) {
        let waiters = fixWaiters
        fixWaiters.removeAll()
        waiters.forEach { $0.resume(returning: coordinate) }
    }

    // MARK: CLLocationManagerDelegate
    // Delivered on the main thread, where the manager was created.

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last.map(Coordinate.init) else { return }
        MainActor.assumeIsolated {
            // A fix someone asked for goes to them; otherwise it's a significant change.
            if fixWaiters.isEmpty {
                onUpdate?(coordinate)
            } else {
                resolveFixWaiters(with: coordinate)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Usually transient (no fix yet); fall back to the last known position.
        MainActor.assumeIsolated { resolveFixWaiters(with: lastKnown) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            let status = authorization
            guard status != .notDetermined else { return }
            let waiters = authorizationWaiters
            authorizationWaiters.removeAll()
            waiters.forEach { $0.resume(returning: status) }
        }
    }
}
