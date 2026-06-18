import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    var gestureManager: GestureManager!

    var workspacePreviewWindow: NSWindow?
    var appPreviewWindow: NSWindow?

    func applicationDidFinishLaunching(
        _ notification: Notification
    ) {

        NSApp.setActivationPolicy(.accessory)

        checkAccessibilityPermissions()

        gestureManager = GestureManager()

        gestureManager.onShowWorkspacePreview = {
            [weak self] in
            self?.showWorkspacePreview()
        }

        gestureManager.onHideWorkspacePreview = {
            [weak self] in
            self?.hideWorkspacePreview()
        }

        gestureManager.onShowAppPreview = {
            [weak self] in
            self?.showAppPreview()
        }

        gestureManager.onHideAppPreview = {
            [weak self] in
            self?.hideAppPreview()
        }

        gestureManager.start()
    }
}

extension AppDelegate {

    private func createCenteredWindow(
        width: CGFloat,
        height: CGFloat,
        contentView: NSView
    ) -> NSWindow {

        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: width,
                height: height
            ),
            styleMask: [
                .borderless,
                .nonactivatingPanel
            ],
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .statusBar

        window.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .transient
        ]

        window.hasShadow = true

        window.contentView = contentView

        return window
    }

    private func center(_ window: NSWindow) {

        guard let screen = NSScreen.main else {
            return
        }

        let sf = screen.visibleFrame

        let x = sf.minX +
            (sf.width - window.frame.width) / 2

        let y = sf.minY +
            (sf.height - window.frame.height) / 2

        window.setFrameOrigin(
            NSPoint(x: x, y: y)
        )
    }

    private func animateShow(
        _ window: NSWindow
    ) {

        center(window)

        window.alphaValue = 0

        window.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup {
            ctx in

            ctx.duration = 0.15

            window.animator().alphaValue = 1
        }
    }

    private func animateHide(
        _ window: NSWindow
    ) {

        NSAnimationContext.runAnimationGroup(
            { ctx in
                ctx.duration = 0.15
                window.animator().alphaValue = 0
            },
            completionHandler: {
                window.orderOut(nil)
            }
        )
    }
}

extension AppDelegate {

    func showWorkspacePreview() {

        if workspacePreviewWindow == nil {

            let view = WorkspacePreviewView(
                gestureManager: gestureManager
            )

            workspacePreviewWindow =
                createCenteredWindow(
                    width: 900,
                    height: 550,
                    contentView:
                        NSHostingView(rootView: view)
                )
        }

        if let window = workspacePreviewWindow {
            animateShow(window)
        }
    }

    func hideWorkspacePreview() {

        guard let window = workspacePreviewWindow
        else {
            return
        }

        animateHide(window)
    }

    func showAppPreview() {

        if appPreviewWindow == nil {

            let view = AppPreviewView(
                gestureManager: gestureManager
            )

            appPreviewWindow =
                createCenteredWindow(
                    width: 900,
                    height: 320,
                    contentView:
                        NSHostingView(rootView: view)
                )
        }

        if let window = appPreviewWindow {
            animateShow(window)
        }
    }

    func hideAppPreview() {

        guard let window = appPreviewWindow
        else {
            return
        }

        animateHide(window)
    }
}
