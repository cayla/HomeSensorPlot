import SwiftUI

/// Status line inside the main window (not the macOS menu bar).
/// The real menu bar status item lives in `macOSBridge`.
struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 12) {
            Label(appState.status.shortLabel, systemImage: appState.status.menuBarSymbol)
            Text(verbatim: appState.settings.exporterEnabled
                   ? "Exporter \(appState.exporterAddress)"
                   : "Exporter off")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 4)
    }
}
