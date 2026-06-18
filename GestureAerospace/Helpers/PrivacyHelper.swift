import Cocoa

func checkAccessibilityPermissions() {

    let options = [
        kAXTrustedCheckOptionPrompt
            .takeRetainedValue() as String: true
    ]

    if !AXIsProcessTrustedWithOptions(
        options as CFDictionary
    ) {

        NSApplication.shared.terminate(nil)
    }
}

final class PrivacyHelper {

    static func isProcessTrustedWithPrompt()
    -> Bool {

        let trusted =
            AXIsProcessTrustedWithOptions(
                [
                    kAXTrustedCheckOptionPrompt
                        .takeUnretainedValue() as String:
                            true
                ] as CFDictionary
            )

        if trusted {
            return true
        }

        promptForAccessibilityPermissionFromSandbox()

        return false
    }

    private static func
    promptForAccessibilityPermissionFromSandbox()
    {
        _ = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest:
                NSEvent.EventTypeMask.gesture.rawValue,
            callback: dummyEventHandler,
            userInfo: nil
        )
    }
}

private func dummyEventHandler(
    proxy: CGEventTapProxy,
    eventType: CGEventType,
    cgEvent: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {

    return Unmanaged.passUnretained(
        cgEvent
    )
}
