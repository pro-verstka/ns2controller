import SwiftUI
import NS2Core

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Запуск") {
                Toggle("Запускать при входе в систему", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                Toggle("Будить контроллер при подключении по USB", isOn: $model.autoWakeEnabled)
                Picker("LED игрока при пробуждении", selection: $model.playerLED) {
                    ForEach(1...4, id: \.self) { Text("Игрок \($0)").tag($0) }
                }
            }
            Section("CLI-демон (LaunchAgent)") {
                LabeledContent("Состояние") {
                    HStack {
                        Text(model.launchAgentActive ? "запущен параллельно с приложением" : "не установлен")
                        if model.launchAgentActive { Button("Отключить") { model.disableLaunchAgent() } }
                    }
                }
                Text("Приложение само будит контроллер, поэтому LaunchAgent из scripts/install.sh больше не нужен. Команды ns2ctl остаются доступны.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let message = model.settingsMessage {
                Section { Text(message).foregroundStyle(.secondary) }
            }
            Section("О программе") {
                Text("ns2controller: Nintendo Switch 2 Pro Controller по USB на macOS без драйверов.")
                Link("github.com/pro-verstka/ns2controller", destination: URL(string: "https://github.com/pro-verstka/ns2controller")!)
                Text("Профили моста: \(KBMProfile.directory.path)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
    }
}
