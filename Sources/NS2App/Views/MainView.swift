import SwiftUI
import NS2Core

enum MainTab: String, CaseIterable {
    case controller, bridge, integrations, logs, settings

    static var initial: MainTab {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--tab"), index + 1 < arguments.count else { return .controller }
        return MainTab(rawValue: arguments[index + 1]) ?? .controller
    }
}

struct MainView: View {
    @State private var tab = MainTab.initial

    var body: some View {
        TabView(selection: $tab) {
            ControllerView().tabItem { Label("Контроллер", systemImage: "gamecontroller") }.tag(MainTab.controller)
            BridgeView().tabItem { Label("Мост", systemImage: "keyboard") }.tag(MainTab.bridge)
            IntegrationsView().tabItem { Label("Интеграции", systemImage: "puzzlepiece.extension") }.tag(MainTab.integrations)
            LogsView().tabItem { Label("Журнал", systemImage: "doc.text.magnifyingglass") }.tag(MainTab.logs)
            SettingsView().tabItem { Label("Настройки", systemImage: "gearshape") }.tag(MainTab.settings)
        }
        .padding(12)
    }
}

struct StatusDot: View {
    var ok: Bool
    var body: some View {
        Circle().fill(ok ? Color.green : Color.secondary.opacity(0.4)).frame(width: 9, height: 9)
    }
}
