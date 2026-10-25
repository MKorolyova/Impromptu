//
//  NotificationService.swift
//  Impromptu-app
//

import Foundation
import UserNotifications

protocol NotificationPosting: AnyObject {
    /// Shows the system prompt the first time; returns whether notifications are allowed.
    func requestAuthorization() async -> Bool
    func isAuthorized() async -> Bool
    /// `route` is the screen tapping the notification opens.
    func post(id: String, title: String, body: String, route: AppRoute) async
}

/// Posts local notifications, and shows them and the server's push notifications (nearby alerts) as banners
/// even while the app is open. Tapping one sends its route to `AppRouter`; pushes carry it as `route` too.
final class LocalNotificationService: NSObject, NotificationPosting, UNUserNotificationCenterDelegate {
    private nonisolated static let routeKey = "route"

    private let center = UNUserNotificationCenter.current()
    private let router: AppRouter

    init(router: AppRouter) {
        self.router = router
        super.init()
        center.delegate = self
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func isAuthorized() async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional || status == .ephemeral
    }

    func post(id: String, title: String, body: String, route: AppRoute) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = route.rawValue
        content.userInfo = [Self.routeKey: route.rawValue]
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let route = (response.notification.request.content.userInfo[Self.routeKey] as? String).flatMap(AppRoute.init(rawValue:))
        await MainActor.run { router.pendingRoute = route }
    }
}
