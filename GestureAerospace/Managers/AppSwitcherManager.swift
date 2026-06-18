import AppKit
import Combine

@MainActor
final class AppSwitcherManager:
    ObservableObject
{

    @Published
    var recentApps:
        [NSRunningApplication] = []

    @Published
    var selectedIndex: Int = 0

    private var observer:
        NSObjectProtocol?

    init() {

        startTracking()
    }

    deinit {

        if let observer {

            NSWorkspace.shared
                .notificationCenter
                .removeObserver(observer)
        }
    }
}

extension AppSwitcherManager {

    private func startTracking() {

        observer =
            NSWorkspace.shared
            .notificationCenter
            .addObserver(
                forName:
                    NSWorkspace
                    .didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in

                guard
                    let app =
                        notification.userInfo?[
                            NSWorkspace
                            .applicationUserInfoKey
                        ]
                        as? NSRunningApplication
                else {
                    return
                }

                self?.recordActivation(
                    app
                )
            }
    }
}

extension AppSwitcherManager {

    private func recordActivation(
        _ app: NSRunningApplication
    ) {

        guard
            app.bundleIdentifier
                != Bundle.main.bundleIdentifier
        else {
            return
        }

        recentApps.removeAll {
            $0.processIdentifier
                == app.processIdentifier
        }

        recentApps.insert(
            app,
            at: 0
        )

        if recentApps.count > 50 {

            recentApps.removeLast(
                recentApps.count - 50
            )
        }
    }
}

extension AppSwitcherManager {

    func appList()
    -> [NSRunningApplication] {

        recentApps.filter {

            !$0.isTerminated
        }
    }

    func currentSelection()
    -> NSRunningApplication? {

        let apps = appList()

        guard
            selectedIndex >= 0,
            selectedIndex < apps.count
        else {
            return nil
        }

        return apps[selectedIndex]
    }
}

extension AppSwitcherManager {

    func resetSelection() {

        selectedIndex = 0
    }

    func moveLeft() {

        let count =
            appList().count

        guard count > 0 else {
            return
        }

        selectedIndex =
            max(
                selectedIndex - 1,
                0
            )
    }

    func moveRight() {

        let count =
            appList().count

        guard count > 0 else {
            return
        }

        selectedIndex =
            min(
                selectedIndex + 1,
                count - 1
            )
    }
}

extension AppSwitcherManager {

    func activateSelected() {

        guard
            let app =
                currentSelection()
        else {
            return
        }

        app.activate(
            options: [
                .activateIgnoringOtherApps
            ]
        )
    }
}

extension AppSwitcherManager {

    func switchBackAndForth() {

        let apps = appList()

        guard apps.count >= 2
        else {
            return
        }

        let previous =
            apps[1]

        previous.activate(
            options: [
                .activateIgnoringOtherApps
            ]
        )
    }
}

extension AppSwitcherManager {

    func icon(
        for app:
        NSRunningApplication
    ) -> NSImage {

        app.icon ??
            NSWorkspace.shared.icon(
                forFileType: "app"
            )
    }

    func appName(
        _ app:
        NSRunningApplication
    ) -> String {

        app.localizedName
            ?? "Unknown"
    }
}
