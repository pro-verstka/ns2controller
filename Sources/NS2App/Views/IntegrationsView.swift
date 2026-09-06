import SwiftUI
import NS2Core

struct IntegrationsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 14) {
            GroupBox("Steam") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Steam видит контроллер через SDL, но его встроенный маппинг для 057e:2069 неверный. Кнопка записывает правильный в config.vdf (с бэкапом). Steam при этом закрывается и запускается снова.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        StatusDot(ok: model.steamStatus == .installed)
                        Text(steamStatusText)
                        Spacer()
                        Text(model.steamRunning ? "Steam запущен" : "Steam закрыт").foregroundStyle(.secondary)
                        Button("Установить маппинг в Steam") { model.installSteamMapping() }
                            .disabled(model.steamStatus == .steamNotFound || model.steamStatus == .installed)
                    }
                }
                .padding(4)
            }
            GroupBox("CrossOver") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Wine получает XInput-геймпад только если у SDL есть маппинг. Он записывается в cxbottle.conf выбранной бутылки как SDL_GAMECONTROLLERCONFIG; ключ winebus\\map, который роняет Wine, удаляется.")
                        .font(.caption).foregroundStyle(.secondary)
                    if CrossOverIntegration.isAvailable {
                        HStack {
                            Picker("Бутылка", selection: $model.selectedBottle) {
                                ForEach(model.bottles, id: \.self) { Text($0).tag($0) }
                            }
                            .frame(width: 260)
                            .onChange(of: model.selectedBottle) { _, _ in model.refreshStatuses() }
                            StatusDot(ok: model.crossOverInstalled)
                            Text(model.crossOverInstalled ? "маппинг установлен" : "не установлен")
                            Spacer()
                            if model.crossOverBusy { ProgressView().controlSize(.small) }
                            Button("Установить маппинг в бутылку") { model.installCrossOverMapping() }
                                .disabled(model.selectedBottle.isEmpty || model.crossOverBusy)
                        }
                    } else {
                        Text("CrossOver не найден в /Applications").foregroundStyle(.secondary)
                    }
                }
                .padding(4)
            }
            if let message = model.integrationMessage {
                Text(message).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var steamStatusText: String {
        switch model.steamStatus {
        case .steamNotFound: return "config.vdf не найден: Steam не установлен?"
        case .notInstalled: return "маппинг не установлен"
        case .installed: return "актуальный маппинг установлен"
        case .outdated: return "установлен другой маппинг"
        }
    }
}
