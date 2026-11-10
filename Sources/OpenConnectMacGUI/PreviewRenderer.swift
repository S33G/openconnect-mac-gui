import AppKit
import SwiftUI

/// Documentation-only rendering. Normal app windows inherit the system appearance.
@MainActor enum PreviewRenderer {
    static func render(to folder: URL) async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let model = AppModel(demo: true)
            let hosting = NSHostingView(rootView: MenuContent(model: model))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 370, height: 700),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: appearance)
            window.contentView = hosting
            window.setContentSize(hosting.fittingSize)
            hosting.layoutSubtreeIfNeeded()
            window.orderBack(nil)
            try await Task.sleep(for: .milliseconds(250))
            hosting.layoutSubtreeIfNeeded()
            guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
                throw CocoaError(.fileWriteUnknown)
            }
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try data.write(to: folder.appendingPathComponent("ui-\(name).png"))
            window.orderOut(nil)
        }
    }
}
