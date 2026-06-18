import SwiftUI

struct SystemOverlayView: View {
    @ObservedObject var manager: InteractionManager
    
    var body: some View {
        VStack {
            if manager.activeOverlay == .workspaces {
                WorkspaceLayoutContainer(manager: manager)
            } else if manager.activeOverlay == .applications {
                ApplicationLayoutContainer(manager: manager)
            }
        }
        .padding(.vertical, 25)
        .padding(.horizontal, 24)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Workspaces View
struct WorkspaceLayoutContainer: View {
    @ObservedObject var manager: InteractionManager
    
    var body: some View {
        let workspaces = manager.workspaceApps.keys.sorted()
        HStack(spacing: 0) {
            ForEach(workspaces, id: \.self) { ws in
                VStack(spacing: 0) {
                    Text(ws)
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundColor(ws == manager.selectedWorkspace ? .white : .primary)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                    
                    VStack(spacing: 0) {
                        ForEach(manager.workspaceApps[ws]?.prefix(8) ?? [], id: \.self) { app in
                            Image(nsImage: AssetIconUtility.getAppIcon(app))
                                .resizable()
                                .frame(width: 115, height: 115)
                                .cornerRadius(22)
                        }
                    }
                    .padding(.bottom, 12)
                    .padding(.horizontal, 9)
                }
                .frame(width: 123)
                .background(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(ws == manager.selectedWorkspace ? Color.gray.opacity(0.4) : Color.clear)
                )
            }
        }
    }
}

// MARK: - Applications View
struct ApplicationLayoutContainer: View {
    @ObservedObject var manager: InteractionManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent Applications")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
            
            HStack(spacing: 12) {
                ForEach(0..<manager.runningApps.count, id: \.self) { index in
                    let app = manager.runningApps[index]
                    VStack(spacing: 12) {
                        Image(nsImage: AssetIconUtility.getAppIcon(app))
                            .resizable()
                            .frame(width: 95, height: 95)
                            .cornerRadius(20)
                        
                        Text(app)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                            .foregroundColor(index == manager.selectedAppIndex ? .white : .secondary)
                    }
                    .padding(14)
                    .frame(width: 125)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(index == manager.selectedAppIndex ? Color.gray.opacity(0.4) : Color.clear)
                    )
                }
            }
        }
    }
}
