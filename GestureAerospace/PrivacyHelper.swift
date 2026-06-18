import Cocoa

class PrivacyHelper {
    static func isProcessTrustedWithPrompt() -> Bool {
        let trusted = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        if trusted {
            return true
        } else {
            promptFromSandbox()
            return false
        }
    }
    
    private static func promptFromSandbox() {
        _ = CGEvent.tapCreate(
            tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: NSEvent.EventTypeMask.gesture.rawValue,
            callback: { _, _, cgEvent, _ in .passUnretained(cgEvent) },
            userInfo: nil
        )
    }
}
