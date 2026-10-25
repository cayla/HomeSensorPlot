import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @State private var tab: Tab = .charts

    private enum Tab: String, CaseIterable, Identifiable {
        case charts = "Charts"
        case inventory = "Inventory"
        case settings = "Settings"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("HomeSensorPlot")
                    .font(.title2.weight(.semibold))
                Spacer()
                statusChip
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Buttons (not a Picker) so re-tapping the active section still resets to its root.
            HStack(spacing: 0) {
                ForEach(Tab.allCases) { item in
                    Button {
                        selectTab(item)
                    } label: {
                        Text(item.rawValue)
                            .font(.subheadline.weight(tab == item ? .semibold : .regular))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(
                                tab == item
                                    ? Color.accentColor.opacity(0.18)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 7)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
            .padding(.horizontal, 16)

            Group {
                switch tab {
                case .charts:
                    ChartsView()
                case .inventory:
                    InventoryView()
                case .settings:
                    SettingsView()
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let warning = appState.storeBootstrapWarning {
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            }
            if let error = appState.lastRefreshError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            appState.start()
            Task { await appState.refreshUI() }
        }
    }

    private func selectTab(_ item: Tab) {
        tab = item
        // Any top-level bar target returns to that section’s root (Charts → category grid).
        appState.resetToSectionRoot()
    }

    private var statusChip: some View {
        Label(appState.status.shortLabel, systemImage: appState.status.menuBarSymbol)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.quaternary, in: Capsule())
    }
}
