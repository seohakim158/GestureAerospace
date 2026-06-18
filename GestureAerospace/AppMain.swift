import SwiftUI

@main
struct GestureWorkspaceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var interactionManager: InteractionManager!
    var overlayWindow: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        checkAccessibilityPermissions()
        
        interactionManager = InteractionManager()
        interactionManager.onShowOverlay = { [weak self] in
            self?.showOverlayWindow()
        }
        interactionManager.onHideOverlay = { [weak self] in
            self?.hideOverlayWindow()
        }
        interactionManager.start()
    }
    
    private func showOverlayWindow() {
        if overlayWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .statusBar
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .transient]
            window.isMovableByWindowBackground = false
            window.hasShadow = true
            window.ignoresMouseEvents = false
            window.styleMask.remove(.titled)
            
            let contentView = SystemOverlayView(manager: interactionManager)
            window.contentView = NSHostingView(rootView: contentView)
            
            overlayWindow = window
        }
        
        if let window = overlayWindow, let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowFrame = window.frame
            let x = (screenFrame.width - windowFrame.width) / 2 + screenFrame.minX
            let y = (screenFrame.height - windowFrame.height) / 2 + screenFrame.minY
            window.setFrameOrigin(NSPoint(x: x, y: y))
            window.alphaValue = 0
            window.orderFrontRegardless()
            
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                window.animator().alphaValue = 1.0
            }
        }
    }
    
    private func hideOverlayWindow() {
        guard let window = overlayWindow else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
        })
    }
}

func checkAccessibilityPermissions() {
    let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
    if !AXIsProcessTrustedWithOptions(options as CFDictionary) {
        _ = try? Process.run(
            URL(filePath: "/usr/bin/tccutil"),
            arguments: ["reset", "Accessibility", Bundle.main.bundleIdentifier ?? "club.mediosz.GestureWorkspace"]
        )
        NSApplication.shared.terminate(nil)
    }
}
