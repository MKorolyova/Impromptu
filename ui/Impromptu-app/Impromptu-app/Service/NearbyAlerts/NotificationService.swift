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
    func post(id: String, title: String, body: String) async
}

/// Local notifications, shown as banners even while the app is open.
final class LocalNotificationService: NSObject, NotificationPosting, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()

    override init() {
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

    func post(id: String, title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = "nearby"
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
