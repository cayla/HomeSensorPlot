import SwiftUI

/// Compact status/actions panel shown at the top of the main window.
/// (Apple marks HomeKit unavailable for native macOS menu-bar apps; this Catalyst build
/// keeps always-on collection via Open at Login instead.)
struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 12) {
            Label(appState.status.shortLabel, systemImage: appState.status.menuBarSymbol)
            Text(verbatim: "Exporter \(appState.exporterAddress)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Collect Now") {
                Task {
                    await appState.collector.forceCollectOnce()
                    await appState.refreshUI()
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 4)
    }
}
