import Foundation
import Combine
import UIKit
import CoreLocation
import AppTrackingTransparency
import AVFoundation
import Photos
import UserNotifications

struct PermissionItem: Identifiable {
    var id: String { title }
    let title: String
    let detail: String
    let statusText: String
    let isGranted: Bool
    let canRequest: Bool
    let needsSettings: Bool
    let request: (() -> Void)?
}

@MainActor
final class PermissionCatalogStore: ObservableObject {
    static let shared = PermissionCatalogStore()

    @Published private(set) var items: [PermissionItem] = []
    private var notificationStatus: UNAuthorizationStatus?

    var grantedCount: Int { items.filter(\.isGranted).count }
    var totalCount: Int { items.count }

    private init() {
        rebuild()
    }

    func refresh() {
        rebuild()
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                guard let self else { return }
                self.notificationStatus = settings.authorizationStatus
                self.rebuild()
            }
        }
    }

    private func rebuild() {
        items = PermissionCatalog.all(notificationStatus: notificationStatus)
    }
}

enum PermissionCatalog {
    static func all(notificationStatus: UNAuthorizationStatus? = nil) -> [PermissionItem] {
        [
            locationItem(),
            trackingItem(),
            photoItem(),
            micItem(),
            cameraItem(),
            notificationItem(status: notificationStatus),
            localNetworkItem()
        ]
    }

    static func entitlements() -> [(String, String)] {
        let path = Bundle.main.path(forResource: "REScout", ofType: "entitlements")
        let candidates = [
            path,
            Bundle.main.bundlePath + "/REScout.entitlements"
        ].compactMap { $0 }
        for c in candidates {
            if let dict = NSDictionary(contentsOfFile: c) as? [String: Any] {
                return dict.keys.sorted().map { key in
                    let value = dict[key]
                    let text: String
                    if let b = value as? Bool { text = b ? "true" : "false" }
                    else if let arr = value as? [Any] { text = "[\(arr.count)]" }
                    else { text = "\(value ?? "")" }
                    return (key, text)
                }
            }
        }
        return [
            ("wifi-info", "expected"),
            ("platform-application", "expected"),
            ("no-sandbox", "expected")
        ]
    }

    private static func locationItem() -> PermissionItem {
        let status = CLLocationManager().authorizationStatus
        let granted = status == .authorizedAlways || status == .authorizedWhenInUse
        let text: String = {
            switch status {
            case .notDetermined: return L10n.tr("Permission Not Determined")
            case .restricted: return L10n.tr("Permission Restricted")
            case .denied: return L10n.tr("Permission Denied")
            case .authorizedWhenInUse: return L10n.tr("Permission When In Use")
            case .authorizedAlways: return L10n.tr("Permission Always")
            @unknown default: return L10n.tr("Permission Unknown")
            }
        }()
        return PermissionItem(
            title: L10n.tr("Permission Location"),
            detail: L10n.tr("Permission Location Detail"),
            statusText: text,
            isGranted: granted,
            canRequest: status == .notDetermined,
            needsSettings: status == .denied || status == .restricted,
            request: {
                NetworkCollector.shared.requestSSIDPermissionIfNeeded()
            }
        )
    }

    private static func trackingItem() -> PermissionItem {
        if #available(iOS 14, *) {
            let status = ATTrackingManager.trackingAuthorizationStatus
            let text: String = {
                switch status {
                case .notDetermined: return L10n.tr("Tracking Not Determined")
                case .restricted: return L10n.tr("Tracking Restricted")
                case .denied: return L10n.tr("Tracking Denied")
                case .authorized: return L10n.tr("Tracking Authorized")
                @unknown default: return L10n.tr("Permission Unknown")
                }
            }()
            return PermissionItem(
                title: L10n.tr("Permission Tracking"),
                detail: L10n.tr("Permission Tracking Detail"),
                statusText: text,
                isGranted: status == .authorized,
                canRequest: status == .notDetermined,
                needsSettings: status == .denied || status == .restricted,
                request: {
                    ActivityLogStore.log(
                        .info,
                        category: L10n.tr("Log Category Permission"),
                        message: L10n.tr("Log Request Tracking")
                    )
                    ATTrackingManager.requestTrackingAuthorization { status in
                        ActivityLogStore.log(
                            .info,
                            category: L10n.tr("Log Category Permission"),
                            message: String(format: L10n.tr("Log Tracking Status Format"), "\(status.rawValue)")
                        )
                    }
                }
            )
        }
        return PermissionItem(
            title: L10n.tr("Permission Tracking"),
            detail: L10n.tr("Permission Tracking Detail"),
            statusText: L10n.tr("Tracking Authorized"),
            isGranted: true,
            canRequest: false,
            needsSettings: false,
            request: nil
        )
    }

    private static func photoItem() -> PermissionItem {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let granted = status == .authorized || status == .limited
        let text: String = {
            switch status {
            case .notDetermined: return L10n.tr("Permission Not Determined")
            case .restricted: return L10n.tr("Permission Restricted")
            case .denied: return L10n.tr("Permission Denied")
            case .authorized: return L10n.tr("Permission Authorized")
            case .limited: return L10n.tr("Permission Limited")
            @unknown default: return L10n.tr("Permission Unknown")
            }
        }()
        return PermissionItem(
            title: L10n.tr("Permission Photos"),
            detail: L10n.tr("Permission Photos Detail"),
            statusText: text,
            isGranted: granted,
            canRequest: status == .notDetermined,
            needsSettings: status == .denied || status == .restricted,
            request: { PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in } }
        )
    }

    private static func micItem() -> PermissionItem {
        mediaItem(
            title: L10n.tr("Permission Microphone"),
            detail: L10n.tr("Permission Microphone Detail"),
            status: AVCaptureDevice.authorizationStatus(for: .audio),
            request: { AVCaptureDevice.requestAccess(for: .audio) { _ in } }
        )
    }

    private static func cameraItem() -> PermissionItem {
        mediaItem(
            title: L10n.tr("Permission Camera"),
            detail: L10n.tr("Permission Camera Detail"),
            status: AVCaptureDevice.authorizationStatus(for: .video),
            request: { AVCaptureDevice.requestAccess(for: .video) { _ in } }
        )
    }

    private static func mediaItem(
        title: String,
        detail: String,
        status: AVAuthorizationStatus,
        request: @escaping () -> Void
    ) -> PermissionItem {
        let text: String = {
            switch status {
            case .notDetermined: return L10n.tr("Permission Not Determined")
            case .restricted: return L10n.tr("Permission Restricted")
            case .denied: return L10n.tr("Permission Denied")
            case .authorized: return L10n.tr("Permission Authorized")
            @unknown default: return L10n.tr("Permission Unknown")
            }
        }()
        return PermissionItem(
            title: title,
            detail: detail,
            statusText: text,
            isGranted: status == .authorized,
            canRequest: status == .notDetermined,
            needsSettings: status == .denied || status == .restricted,
            request: request
        )
    }

    private static func notificationItem(status: UNAuthorizationStatus?) -> PermissionItem {
        var statusText = L10n.tr("Permission See System Settings")
        var granted = false
        var canRequest = false
        var needsSettings = false
        if let status {
            switch status {
            case .notDetermined:
                statusText = L10n.tr("Permission Not Determined")
                canRequest = true
                needsSettings = false
            case .denied:
                statusText = L10n.tr("Permission Denied")
                needsSettings = true
            case .authorized, .provisional, .ephemeral:
                statusText = L10n.tr("Permission Authorized")
                granted = true
                needsSettings = false
            @unknown default:
                statusText = L10n.tr("Permission Unknown")
            }
        }
        return PermissionItem(
            title: L10n.tr("Permission Notifications"),
            detail: L10n.tr("Permission Notifications Detail"),
            statusText: statusText,
            isGranted: granted,
            canRequest: canRequest,
            needsSettings: needsSettings,
            request: {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in
                    DispatchQueue.main.async {
                        PermissionCatalogStore.shared.refresh()
                    }
                }
            }
        )
    }

    private static func localNetworkItem() -> PermissionItem {
        PermissionItem(
            title: L10n.tr("Permission Local Network"),
            detail: L10n.tr("Permission Local Network Detail"),
            statusText: L10n.tr("Permission See System Settings"),
            isGranted: false,
            canRequest: false,
            needsSettings: true,
            request: nil
        )
    }
}
