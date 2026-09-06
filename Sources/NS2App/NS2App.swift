import AppKit
import SwiftUI
import NS2Core

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?

    func applicationWillTerminate(_ notification: Notification) {
        model?.shutdown()
    }
}

@main
struct NS2App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environment(model)
        } label: {
            Image(systemName: model.hidAttached ? "gamecontroller.fill" : "gamecontroller")
        }
        .onChange(of: model.started, initial: true) { _, _ in
            delegate.model = model
            model.startIfNeeded()
        }

        Window("NS2 Controller", id: "main") {
            MainView()
                .environment(model)
                .frame(minWidth: 760, minHeight: 560)
        }
        .defaultSize(width: 860, height: 640)
        .defaultLaunchBehavior(.presented)
    }
}

struct MenuContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.statusLine)
        Divider()
        Button("Разбудить контроллер") { model.wakeNow() }
            .disabled(!model.usbPresent)
        Button(model.bridgeRunning ? "Остановить мост" : "Запустить мост (\(model.selectedProfile))") {
            model.bridgeRunning ? model.stopBridge() : model.startBridge()
        }
        if model.bridgeRunning {
            Button(model.bridgePaused ? "Снять паузу" : "Пауза моста") { model.setBridgePaused(!model.bridgePaused) }
        }
        Divider()
        Button("Открыть окно") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Выход") { NSApp.terminate(nil) }
    }
}
