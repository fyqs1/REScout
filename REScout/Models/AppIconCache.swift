import Foundation
import UIKit
import SwiftUI

enum AppIconCache {
    private static let lock = NSLock()
    private static var memory: [String: UIImage] = [:]
    private static var inFlight: Set<String> = []
    private static let loadQueue = DispatchQueue(label: "com.fyqs.REScout.icons", qos: .utility)

    static func cached(for key: String) -> UIImage? {
        lock.lock()
        defer { lock.unlock() }
        return memory[key]
    }

    static func load(bundleID: String, appBundlePath: String, completion: @escaping (UIImage?) -> Void) {
        let key = bundleID.isEmpty ? appBundlePath : bundleID
        guard !key.isEmpty else {
            DispatchQueue.main.async { completion(nil) }
            return
        }

        lock.lock()
        if let hit = memory[key] {
            lock.unlock()
            DispatchQueue.main.async { completion(hit) }
            return
        }
        if inFlight.contains(key) {
            lock.unlock()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.35) {
                load(bundleID: bundleID, appBundlePath: appBundlePath, completion: completion)
            }
            return
        }
        inFlight.insert(key)
        lock.unlock()

        loadQueue.async {
            let data = DOVIconDataForBundleID(
                bundleID.isEmpty ? nil : bundleID,
                appBundlePath.isEmpty ? nil : appBundlePath
            ) as Data?
            let image = data.flatMap { UIImage(data: $0) }
            lock.lock()
            inFlight.remove(key)
            if let image {
                memory[key] = image
            }
            lock.unlock()
            DispatchQueue.main.async { completion(image) }
        }
    }

    /// `/var/.../Foo.app/Foo` → `/var/.../Foo.app`
    static func appBundlePath(fromExecutablePath path: String) -> String {
        guard !path.isEmpty else { return "" }
        let ns = path as NSString
        if ns.pathExtension.lowercased() == "app" { return path }
        let parent = ns.deletingLastPathComponent
        if (parent as NSString).pathExtension.lowercased() == "app" {
            return parent
        }
        return parent
    }
}

/// Loads a 44/64pt app icon on first appear. List inventory no longer embeds PNG data.
struct LazyAppIcon: View {
    let bundleID: String
    let bundlePath: String
    var size: CGFloat = 44
    var cornerRadius: CGFloat = 10

    @State private var image: UIImage?

    private var cacheKey: String {
        bundleID.isEmpty ? bundlePath : bundleID
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.secondary.opacity(0.15))
                    Image(systemName: "app.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onAppear(perform: load)
    }

    private func load() {
        if let cached = AppIconCache.cached(for: cacheKey) {
            image = cached
            return
        }
        AppIconCache.load(bundleID: bundleID, appBundlePath: bundlePath) { img in
            image = img
        }
    }
}
