import LinkPresentation
import UniformTypeIdentifiers
import UIKit
import SwiftUI

/// Presents `UIActivityViewController` from a real UIKit controller, anchored to a button.
/// SwiftUI `.sheet` wrapping the share sheet, and presenting from a mid-screen view,
/// both crash on 更多 (nil popover `sourceView`).
enum ShareSheetPresenter {
    private static var isPresenting = false

    static func present(items: [Any], from sourceView: UIView?, completion: (() -> Void)? = nil) {
        DispatchQueue.main.async {
            guard !items.isEmpty else {
                completion?()
                return
            }
            if isPresenting {
                completion?()
                return
            }

            let presenter = viewController(for: sourceView) ?? topViewController()
            guard let presenter, !presenter.isBeingDismissed else {
                completion?()
                return
            }
            if presenter.presentedViewController is UIActivityViewController {
                completion?()
                return
            }

            let controller = AnchoredActivityViewController(
                activityItems: items,
                applicationActivities: nil
            )
            let anchor = sourceView ?? presenter.navigationController?.navigationBar ?? presenter.view
            controller.shareAnchor = anchor
            controller.completionWithItemsHandler = { _, _, _, _ in
                DispatchQueue.main.async {
                    isPresenting = false
                    completion?()
                }
            }
            fillPopover(controller.popoverPresentationController, anchor: anchor)

            isPresenting = true
            presenter.present(controller, animated: true) {
                if presenter.presentedViewController == nil {
                    isPresenting = false
                    completion?()
                }
            }
        }
    }

    static func presentFileURLs(_ urls: [URL], from sourceView: UIView?, completion: (() -> Void)? = nil) {
        let items: [Any] = urls.prefix(1).map { url in
            FileActivityItem(url: url, typeIdentifier: typeIdentifier(for: url))
        }
        present(items: items, from: sourceView, completion: completion)
    }

    static func typeIdentifier(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if let type = UTType(filenameExtension: ext) {
            return type.identifier
        }
        switch ext {
        case "json": return "public.json"
        case "txt", "text", "md": return "public.plain-text"
        case "plist": return "com.apple.property-list"
        default: return "public.data"
        }
    }

    fileprivate static func fillPopover(_ popover: UIPopoverPresentationController?, anchor: UIView?) {
        guard let popover else { return }
        let view = anchor
            ?? popover.sourceView
            ?? popover.presentingViewController.view
        guard let view else { return }
        popover.sourceView = view
        popover.sourceRect = view.bounds
        popover.permittedArrowDirections = view is UINavigationBar ? [] : [.up, .down]
        popover.canOverlapSourceViewRect = true
        popover.barButtonItem = nil
    }

    private static func viewController(for view: UIView?) -> UIViewController? {
        var responder: UIResponder? = view
        while let current = responder {
            if let vc = current as? UIViewController {
                return vc
            }
            responder = current.next
        }
        return nil
    }

    private static func topViewController(base: UIViewController? = nil) -> UIViewController? {
        let root = base ?? activeWindow()?.rootViewController
        if let nav = root as? UINavigationController {
            return topViewController(base: nav.visibleViewController ?? nav.topViewController)
        }
        if let tab = root as? UITabBarController {
            return topViewController(base: tab.selectedViewController)
        }
        if let split = root as? UISplitViewController {
            return topViewController(base: split.viewControllers.last)
        }
        if let presented = root?.presentedViewController {
            if presented is UIAlertController || presented is UIActivityViewController {
                return root
            }
            return topViewController(base: presented)
        }
        return root
    }

    private static func activeWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let preferred = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return preferred?.windows.first(where: \.isKeyWindow) ?? preferred?.windows.first
    }
}

/// Injects a popover source when 更多 presents another controller.
final class AnchoredActivityViewController: UIActivityViewController, UIPopoverPresentationControllerDelegate {
    weak var shareAnchor: UIView?

    override func present(
        _ viewControllerToPresent: UIViewController,
        animated flag: Bool,
        completion: (() -> Void)? = nil
    ) {
        prepareNestedPresentation(viewControllerToPresent)
        super.present(viewControllerToPresent, animated: flag, completion: completion)
    }

    override func show(_ vc: UIViewController, sender: Any?) {
        prepareNestedPresentation(vc)
        super.show(vc, sender: sender)
    }

    override func showDetailViewController(_ vc: UIViewController, sender: Any?) {
        prepareNestedPresentation(vc)
        super.showDetailViewController(vc, sender: sender)
    }

    func prepareForPopoverPresentation(_ popoverPresentationController: UIPopoverPresentationController) {
        if popoverPresentationController.sourceView == nil,
           popoverPresentationController.barButtonItem == nil {
            ShareSheetPresenter.fillPopover(popoverPresentationController, anchor: nestedAnchor)
        }
    }

    private func prepareNestedPresentation(_ viewController: UIViewController) {
        if let popover = viewController.popoverPresentationController {
            popover.delegate = self
            ShareSheetPresenter.fillPopover(popover, anchor: nestedAnchor)
        }
    }

    private var nestedAnchor: UIView? {
        shareAnchor ?? viewIfLoaded ?? presentingViewController?.view
    }
}

final class FileActivityItem: NSObject, UIActivityItemSource {
    let url: URL
    let typeIdentifier: String

    init(url: URL, typeIdentifier: String) {
        self.url = url
        self.typeIdentifier = typeIdentifier
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        url
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        url
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        typeIdentifier
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        url.lastPathComponent
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = url.lastPathComponent
        metadata.originalURL = url
        metadata.url = url
        return metadata
    }
}

/// Navigation-bar share button that owns a real `UIView` for popover anchoring.
struct ShareToolbarButton: UIViewRepresentable {
    var accessibilityLabel: String
    var isEnabled: Bool = true
    var action: (UIView) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeUIView(context: Context) -> UIButton {
        let button = ShareBarButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        button.setImage(UIImage(systemName: "square.and.arrow.up", withConfiguration: config), for: .normal)
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped(_:)), for: .touchUpInside)
        button.accessibilityLabel = accessibilityLabel
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }

    func updateUIView(_ uiView: UIButton, context: Context) {
        uiView.isEnabled = isEnabled
        uiView.accessibilityLabel = accessibilityLabel
        context.coordinator.action = action
    }

    final class Coordinator: NSObject {
        var action: (UIView) -> Void

        init(action: @escaping (UIView) -> Void) {
            self.action = action
        }

        @objc func tapped(_ sender: UIButton) {
            action(sender)
        }
    }
}

private final class ShareBarButton: UIButton {
    override var intrinsicContentSize: CGSize {
        CGSize(width: 36, height: 44)
    }
}
