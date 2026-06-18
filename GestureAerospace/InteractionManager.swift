import Cocoa
import Foundation
import Socket
import SwiftUI
import Combine
import os

enum OverlayType {
    case none
    case workspaces
    case applications
}

enum NavigationDirection {
    case left
    case right
}

enum EdgeSwipeDirection {
    case next
    case prev
    var value: String { self == .next ? "next" : "prev" }
}

enum InteractionError: Error {
    case socketError(String)
    case commandFail(String)
}

public struct ClientRequest: Codable, Sendable {
    public let command: String = ""
    public let args: [String]
    public let stdin: String
}

public struct ServerAnswer: Codable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let serverVersionAndHash: String
}

@MainActor
class InteractionManager: ObservableObject {
    
    private enum FingerVector {
        case left, right, up, down
    }
    
    // UI States
    @Published var activeOverlay: OverlayType = .none
    @Published var workspaceApps: [String: [String]] = [:]
    @Published var selectedWorkspace: String = ""
    
    @Published var runningApps: [String] = []
    @Published var selectedAppIndex: Int = 0
    
    var onShowOverlay: (() -> Void)?
    var onHideOverlay: (() -> Void)?
    
    // Gesture States
    private var eventTap: CFMachPort? = nil
    private var socket: Socket? = nil
    private var gestureInProgress = false
    private var activeFingerCount = 0
    private var prevTouchPositions: [String: NSPoint] = [:]
    
    private var accDisX: Float = 0
    private var accDisY: Float = 0
    private var verticalLocked = false
    private var horizontalLocked = false
    
    private var gestureStartTime: Date?
    private let longPressThresholdMs: Double = 100.0 // Kept at original project speed
    private var navigationMode = false
    private var actionTriggered = false
    private var hasOpenedFallback = false
    
    private var recentApps: [String] = []
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "GestureWorkspace", category: "GestureEngine")
    
    private func runCommand(args: [String], stdin: String, retry: Bool = false) -> Result<String, InteractionError> {
        guard let socket = self.socket else {
            return .failure(.socketError("No active socket connection"))
        }
        do {
            let request = try JSONEncoder().encode(ClientRequest(args: args, stdin: stdin))
            try socket.write(from: request)
            let _ = try Socket.wait(for: [socket], timeout: 0, waitForever: true)
            var answer = Data()
            try socket.read(into: &answer)
            let result = try JSONDecoder().decode(ServerAnswer.self, from: answer)
            if result.exitCode != 0 { return .failure(.commandFail(result.stderr)) }
            return .success(result.stdout)
        } catch {
            if retry { return .failure(.socketError(error.localizedDescription)) }
            connectSocket(reconnect: true)
            return runCommand(args: args, stdin: stdin, retry: true)
        }
    }
    
    func connectSocket(reconnect: Bool = false) {
        if socket != nil && !reconnect { return }
        let path = "/tmp/bobko.aerospace-\(NSUserName()).sock"
        do {
            socket = try Socket.create(family: .unix, type: .stream, proto: .unix)
            try socket?.connect(to: path)
            logger.info("Connected to AeroSpace Unix Socket.")
        } catch {
            logger.error("Socket error: \(error.localizedDescription)")
        }
    }
    
    private func updateActiveAppList() {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isTerminated }
            .compactMap { $0.localizedName }
        
        var ordered: [String] = []
        for app in recentApps where apps.contains(app) { ordered.append(app) }
        for app in apps where !ordered.contains(app) { ordered.append(app) }
        
        if let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName {
            if let index = ordered.firstIndex(of: frontApp) {
                ordered.remove(index)
            }
            ordered.insert(frontApp, at: 0)
        }
        
        self.runningApps = ordered
        self.recentApps = ordered
    }
    
    func start() {
        if eventTap != nil { return }
        
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let name = app.localizedName else { return }
            self?.updateRecentAppQueue(activated: name)
        }
        
        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: NSEvent.EventTypeMask.gesture.rawValue,
            callback: { proxy, type, cgEvent, me in
                let wrapper = Unmanaged<InteractionManager>.fromOpaque(me!).takeUnretainedValue()
                return wrapper.handleEventTap(proxy: proxy, type: type, cgEvent: cgEvent)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        
        if let eventTap = eventTap {
            let source = CFMachPortCreateRunLoopSource(nil, eventTap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, CFRunLoopMode.commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
        connectSocket()
        updateActiveAppList()
    }
    
    private func updateRecentAppQueue(activated name: String) {
        if let index = recentApps.firstIndex(of: name) { recentApps.remove(index) }
        recentApps.insert(name, at: 0)
    }
    
    private func handleEventTap(proxy: CGEventTapProxy, type: CGEventType, cgEvent: CGEvent) -> Unmanaged<CGEvent>? {
        if type.rawValue == NSEvent.EventType.gesture.rawValue, let nsEvent = NSEvent(cgEvent: cgEvent) {
            processTouchEvent(nsEvent)
        } else if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
            if let eventTap = eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
        }
        return Unmanaged.passUnretained(cgEvent)
    }
    
    private func processTouchEvent(_ nsEvent: NSEvent) {
        let touches = nsEvent.allTouches()
        if touches.isEmpty { return }
        
        let activeTouches = touches.filter {
            switch $0.phase {
            case .began, .moved, .stationary: return true
            default: return false
            }
        }
        
        if activeTouches.count < 3 || activeTouches.count > 4 {
            if gestureInProgress { finalizeGestureState() }
            return
        }
        
        let currentCount = activeTouches.count
        
        if !gestureInProgress {
            gestureInProgress = true
            activeFingerCount = currentCount
            actionTriggered = false
            hasOpenedFallback = false
            accDisX = 0
            accDisY = 0
            prevTouchPositions.removeAll()
            gestureStartTime = Date()
            navigationMode = (activeOverlay != .none)
            return
        }
        
        if currentCount != activeFingerCount {
            triggerFallbackApp()
            return
        }
        
        if actionTriggered && !navigationMode { return }
        
        var totalX: Float = 0
        var totalY: Float = 0
        var vectors: [FingerVector] = []
        
        for touch in activeTouches {
            let id = "\(touch.identity)"
            let pos = touch.normalizedPosition
            
            guard let prev = prevTouchPositions[id] else {
                prevTouchPositions[id] = pos
                continue
            }
            
            let dx = Float(pos.x - prev.x)
            let dy = Float(pos.y - prev.y)
            totalX += dx
            totalY += dy
            
            vectors.append(abs(dx) > abs(dy) ? (dx > 0 ? .right : .left) : (dy > 0 ? .up : .down))
            prevTouchPositions[id] = pos
        }
        
        if vectors.count < activeFingerCount { return }
        
        accDisX += totalX
        accDisY += totalY
        
        let lefts = vectors.filter { $0 == .left }.count
        let rights = vectors.filter { $0 == .right }.count
        let downs = vectors.filter { $0 == .down }.count
        
        let motionThreshold: Float = 0.010 // Preserved original threshold
        if abs(totalX) < motionThreshold && abs(totalY) < motionThreshold { return }
        
        if !verticalLocked && !horizontalLocked {
            if abs(accDisY) > abs(accDisX) { verticalLocked = true }
            else { horizontalLocked = true }
        }
        
        if navigationMode {
            if horizontalLocked {
                if lefts == activeFingerCount {
                    actionTriggered = true
                    shiftHighlightSelection(to: .left)
                    accDisX = 0; horizontalLocked = false
                } else if rights == activeFingerCount {
                    actionTriggered = true
                    shiftHighlightSelection(to: .right)
                    accDisX = 0; horizontalLocked = false
                }
            }
            return
        }
        
        if horizontalLocked && !verticalLocked {
            if activeFingerCount == 3 {
                if lefts == 3 {
                    actionTriggered = true
                    switchWorkspaceEdge(direction: .prev)
                } else if rights == 3 {
                    actionTriggered = true
                    switchWorkspaceEdge(direction: .next)
                }
            } else {
                triggerFallbackApp()
            }
        } else if verticalLocked && !horizontalLocked {
            if downs == activeFingerCount {
                guard let startTime = gestureStartTime else { return }
                let elapsed = Date().timeIntervalSince(startTime) * 1000
                
                if elapsed > longPressThresholdMs {
                    actionTriggered = true
                    navigationMode = true
                    launchSystemOverlay(type: activeFingerCount == 3 ? .workspaces : .applications)
                }
            } else {
                triggerFallbackApp()
            }
        }
    }
    
    private func finalizeGestureState() {
        guard gestureInProgress else { return }
        
        if activeOverlay != .none {
            if activeOverlay == .workspaces {
                if !selectedWorkspace.isEmpty {
                    _ = runCommand(args: ["workspace", selectedWorkspace], stdin: "")
                }
            } else if activeOverlay == .applications {
                if selectedAppIndex < runningApps.count {
                    let appName = runningApps[selectedAppIndex]
                    NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == appName })?.activate(options: .activateIgnoringOtherApps)
                }
            }
            clearOverlayContext()
        } else if !actionTriggered && !hasOpenedFallback {
            if accDisY < -0.045 { // Unified timing/distance specs
                if activeFingerCount == 3 {
                    executeQuickWorkspaceSwitch()
                } else if activeFingerCount == 4 {
                    executeQuickAppSwitch()
                }
            } else {
                triggerFallbackApp()
            }
        }
        
        resetGestureVariables()
    }
    
    private func resetGestureVariables() {
        gestureInProgress = false
        accDisX = 0; accDisY = 0
        verticalLocked = false; horizontalLocked = false
        gestureStartTime = nil
        navigationMode = false
        actionTriggered = false
        hasOpenedFallback = false
        prevTouchPositions.removeAll()
    }
    
    private func launchSystemOverlay(type: OverlayType) {
        if type == .workspaces {
            fetchAeroSpaceEnvironment()
        } else {
            updateActiveAppList()
            DispatchQueue.main.async {
                self.selectedAppIndex = min(1, self.runningApps.count - 1)
                if self.selectedAppIndex < 0 { self.selectedAppIndex = 0 }
                self.activeOverlay = .applications
                self.onShowOverlay?()
            }
        }
    }
    
    private func clearOverlayContext() {
        activeOverlay = .none
        workspaceApps = [:]
        selectedWorkspace = ""
        runningApps = []
        onHideOverlay?()
    }
    
    private func shiftHighlightSelection(to direction: NavigationDirection) {
        if activeOverlay == .workspaces {
            let sorted = workspaceApps.keys.sorted()
            guard let index = sorted.firstIndex(of: selectedWorkspace) else { return }
            let target = direction == .right ? min(index + 1, sorted.count - 1) : max(index - 1, 0)
            if target != index { selectedWorkspace = sorted[target] }
        } else if activeOverlay == .applications {
            let count = runningApps.count
            guard count > 0 else { return }
            let target = direction == .right ? min(selectedAppIndex + 1, count - 1) : max(selectedAppIndex - 1, 0)
            selectedAppIndex = target
        }
    }
    
    private func executeQuickWorkspaceSwitch() {
        let res = runCommand(args: ["list-workspaces", "--monitor", "focused", "--empty", "no", "--count"], stdin: "")
        if case .success(let stdout) = res {
            let count = Int(stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            if count >= 2 {
                _ = runCommand(args: ["workspace-back-and-forth"], stdin: "")
            }
        }
    }
    
    private func executeQuickAppSwitch() {
        updateActiveAppList()
        guard runningApps.count >= 2 else { return }
        let targetApp = runningApps[1]
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == targetApp }) {
            app.activate(options: .activateIgnoringOtherApps)
        }
    }
    
    private func triggerFallbackApp() {
        guard !hasOpenedFallback else { return }
        hasOpenedFallback = true
        actionTriggered = true
        
        let appURL = URL(fileURLWithPath: "/Applications/LaunchNext.app")
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, _ in }
    }
    
    private func switchWorkspaceEdge(direction: EdgeSwipeDirection) {
        let listResult = runCommand(args: ["list-workspaces", "--monitor", "focused", "--empty", "no"], stdin: "")
        guard case .success(let output) = listResult else { return }
        
        let filtered = output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0 != "􀎡" }
            .joined(separator: "\n")
        
        _ = runCommand(args: ["workspace", direction.value, "--stdin"], stdin: filtered)
    }
    
    private func fetchAeroSpaceEnvironment() {
        let res = runCommand(args: ["list-windows", "--all", "--format", "workspace=%{workspace}, app=%{app-name}"], stdin: "")
        guard case .success(let stdout) = res else { return }
        
        var workspaces: [String: [String]] = [:]
        stdout.split(separator: "\n").forEach { line in
            let comps = line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard comps.count == 2 else { return }
            let ws = comps[0].replacingOccurrences(of: "workspace=", with: "")
            let app = comps[1].replacingOccurrences(of: "app=", with: "")
            workspaces[ws, default: []].append(app)
        }
        
        let focusRes = runCommand(args: ["list-workspaces", "--focused"], stdin: "")
        var currentWorkspace = ""
        if case .success(let ws) = focusRes {
            currentWorkspace = ws.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        DispatchQueue.main.async {
            self.workspaceApps = workspaces
            let nonEmpty = workspaces.filter { !$0.value.isEmpty }.keys.sorted()
            if let apps = workspaces[currentWorkspace], !apps.isEmpty {
                self.selectedWorkspace = currentWorkspace
            } else {
                self.selectedWorkspace = nonEmpty.first ?? currentWorkspace
            }
            self.activeOverlay = .workspaces
            self.onShowOverlay?()
        }
    }
}
