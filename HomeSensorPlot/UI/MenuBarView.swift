import SwiftUI

/// Compact status/actions strip inside the main window (not the macOS menu bar).
/// The real menu bar status item lives in `macOSBridge`.
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
