import AppKit
import Foundation

struct AssetIconUtility {
    static func getAppIcon(_ app: String) -> NSImage {
        let targets = [
            "/Applications/\(app).app",
            "/System/Applications/\(app).app",
            "/Applications/Utilities/\(app).app"
        ]
        
        for location in targets {
            if FileManager.default.fileExists(atPath: location) {
                return NSWorkspace.shared.icon(forFile: location)
            }
        }
        
        let bundleIds: [String: String] = [
            "System Settings": "com.apple.systempreferences",
            "iTerm2": "com.googlecode.iterm2",
            "Finder": "com.apple.finder",
            "Terminal": "com.apple.Terminal",
            "Activity Monitor": "com.apple.ActivityMonitor",
            "Code": "com.microsoft.VSCode"
        ]
        
        if let bundleId = bundleIds[app],
           let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)?.path {
            return NSWorkspace.shared.icon(forFile: path)
        }
        
        return NSWorkspace.shared.icon(forFileType: "app")
    }
}
