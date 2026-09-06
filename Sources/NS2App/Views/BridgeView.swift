import AppKit
import SwiftUI
import NS2Core

struct BridgeView: View {
    @Environment(AppModel.self) private var model
    @State private var newProfileName = ""

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Picker("Профиль", selection: $model.selectedProfile) {
                    ForEach(model.profiles, id: \.self) { Text($0).tag($0) }
                }
                .frame(width: 240)
                TextField("новый профиль", text: $newProfileName).frame(width: 150)
                    .onSubmit { model.createProfile(named: newProfileName); newProfileName = "" }
                Button("Создать") { model.createProfile(named: newProfileName); newProfileName = "" }
                    .disabled(newProfileName.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Удалить") { model.deleteSelectedProfile() }.disabled(model.profiles.count <= 1)
                Spacer()
                if model.bridgeRunning {
                    Button(model.bridgePaused ? "Продолжить" : "Пауза") { model.setBridgePaused(!model.bridgePaused) }
                }
                Button(model.bridgeRunning ? "Остановить мост" : "Запустить мост") {
                    model.bridgeRunning ? model.stopBridge() : model.startBridge()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.inputAvailable && !model.bridgeRunning)
            }
            HStack(spacing: 8) {
                Image(systemName: model.accessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(model.accessibilityTrusted ? .green : .orange)
                Text(model.accessibilityTrusted ? "Accessibility разрешён" : "Нужно разрешение Accessibility, иначе клавиши и мышь не сработают")
                if !model.accessibilityTrusted { Button("Открыть настройки") { model.requestAccessibility() } }
                Spacer()
                Text(model.bridgeRunning ? (model.bridgePaused ? "на паузе" : "работает") : "остановлен").foregroundStyle(.secondary)
            }
            if let profile = Binding($model.editingProfile) {
                ProfileEditorView(profile: profile)
            } else {
                Text("Профиль не загружен").foregroundStyle(.secondary)
                Spacer()
            }
            HStack {
                Button("Сохранить профиль") { model.saveEditedProfile() }.disabled(model.editingProfile == nil)
                Button("Отменить изменения") { model.loadProfileForEditing() }
                if let message = model.editorMessage {
                    Text(message).foregroundStyle(model.editorIsError ? .red : .secondary).lineLimit(2)
                }
                Spacer()
            }
        }
    }
}

struct ProfileEditorView: View {
    @Binding var profile: KBMProfile

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                GroupBox("Стики") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 24) {
                            StickEditor(title: "Левый стик", config: $profile.leftStick)
                            StickEditor(title: "Правый стик", config: $profile.rightStick)
                        }
                        HStack {
                            Text("Мёртвая зона")
                            Slider(value: $profile.deadzone, in: 0...0.5)
                            Text(String(format: "%.2f", profile.deadzone)).monospacedDigit().frame(width: 40, alignment: .trailing)
                        }
                    }
                    .padding(4)
                }
                GroupBox("Кнопки") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), alignment: .leading)], alignment: .leading, spacing: 6) {
                        ForEach(ProController2Button.allCases, id: \.self) { button in
                            HStack {
                                Text(button.name).frame(width: 100, alignment: .leading)
                                KeyField(value: binding(for: button))
                            }
                        }
                    }
                    .padding(4)
                }
                GroupBox("Пауза моста") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Удержание этих кнопок ставит мост на паузу и снимает её; сами кнопки на клавиши не транслируются.")
                            .font(.caption).foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)], alignment: .leading, spacing: 4) {
                            ForEach(ProController2Button.allCases, id: \.self) { button in
                                Toggle(button.name, isOn: comboBinding(for: button)).toggleStyle(.checkbox)
                            }
                        }
                        HStack {
                            Text("Удержание, с")
                            Slider(value: holdBinding, in: 0.3...3)
                            Text(String(format: "%.1f", profile.pauseHoldSeconds ?? 1.0)).monospacedDigit().frame(width: 40, alignment: .trailing)
                        }
                    }
                    .padding(4)
                }
            }
        }
    }

    private func binding(for button: ProController2Button) -> Binding<String> {
        Binding(
            get: { profile.buttons[button.profileKey].flatMap { $0 } ?? "" },
            set: { value in
                let trimmed = value.trimmingCharacters(in: .whitespaces)
                profile.buttons[button.profileKey] = .some(trimmed.isEmpty ? nil : trimmed)
            })
    }

    private func comboBinding(for button: ProController2Button) -> Binding<Bool> {
        Binding(
            get: { profile.pauseCombo.contains(button.profileKey) },
            set: { on in
                if on {
                    if !profile.pauseCombo.contains(button.profileKey) { profile.pauseCombo.append(button.profileKey) }
                } else {
                    profile.pauseCombo.removeAll { $0 == button.profileKey }
                }
            })
    }

    private var holdBinding: Binding<Double> {
        Binding(get: { profile.pauseHoldSeconds ?? 1.0 }, set: { profile.pauseHoldSeconds = $0 })
    }
}

struct StickEditor: View {
    var title: String
    @Binding var config: StickConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker(title, selection: $config.mode) {
                Text("клавиши").tag(StickMode.keys)
                Text("мышь").tag(StickMode.mouse)
                Text("выкл").tag(StickMode.none)
            }
            .frame(width: 260)
            switch config.mode {
            case .keys:
                HStack {
                    Text("Порог")
                    Slider(value: optional(\.threshold, default: 0.5), in: 0.1...0.9)
                    Text(String(format: "%.2f", config.threshold ?? 0.5)).monospacedDigit().frame(width: 40, alignment: .trailing)
                }
                Grid(alignment: .leading, verticalSpacing: 4) {
                    GridRow { Text("Вверх").frame(width: 60, alignment: .leading); KeyField(value: optionalString(\.up)) }
                    GridRow { Text("Вниз").frame(width: 60, alignment: .leading); KeyField(value: optionalString(\.down)) }
                    GridRow { Text("Влево").frame(width: 60, alignment: .leading); KeyField(value: optionalString(\.left)) }
                    GridRow { Text("Вправо").frame(width: 60, alignment: .leading); KeyField(value: optionalString(\.right)) }
                }
            case .mouse:
                HStack {
                    Text("Скорость")
                    Slider(value: optional(\.sensitivity, default: 1200), in: 200...4000)
                    Text("\(Int(config.sensitivity ?? 1200)) px/с").monospacedDigit().frame(width: 80, alignment: .trailing)
                }
                HStack {
                    Text("Кривая")
                    Slider(value: optional(\.curve, default: 1.5), in: 0.5...3)
                    Text(String(format: "%.1f", config.curve ?? 1.5)).monospacedDigit().frame(width: 40, alignment: .trailing)
                }
                Toggle("Инвертировать вертикаль", isOn: Binding(get: { config.invertY ?? false }, set: { config.invertY = $0 }))
                Toggle("Держать курсор в центре окна (камера)", isOn: Binding(get: { config.recenter ?? true }, set: { config.recenter = $0 }))
            case .none:
                Text("Стик не используется").foregroundStyle(.secondary)
            }
        }
        .frame(width: 320, alignment: .leading)
    }

    private func optional(_ keyPath: WritableKeyPath<StickConfig, Double?>, default value: Double) -> Binding<Double> {
        Binding(get: { config[keyPath: keyPath] ?? value }, set: { config[keyPath: keyPath] = $0 })
    }

    private func optionalString(_ keyPath: WritableKeyPath<StickConfig, String?>) -> Binding<String> {
        Binding(get: { config[keyPath: keyPath] ?? "" }, set: { config[keyPath: keyPath] = $0.isEmpty ? nil : $0 })
    }
}

struct KeyField: View {
    @Binding var value: String
    @State private var recording = false
    @State private var monitor: Any?

    private static let mouseNames = ["mouse_left", "mouse_right", "mouse_middle", "mouse_4", "mouse_5", "scroll_up", "scroll_down"]

    var body: some View {
        HStack(spacing: 4) {
            TextField("не назначена", text: $value)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 120)
                .foregroundStyle(value.isEmpty || KeyTable.binding(for: value) != nil ? Color.primary : Color.red)
            Button(recording ? "…" : "Записать") { recording ? stopRecording() : startRecording() }
                .frame(width: 70)
            Menu {
                ForEach(Self.mouseNames, id: \.self) { name in
                    Button(name) { value = name }
                }
                Divider()
                Button("Очистить") { value = "" }
            } label: {
                Image(systemName: "computermouse")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .scrollWheel]) { event in
            var captured: String?
            switch event.type {
            case .keyDown:
                if event.keyCode == 53 { stopRecording(); return nil }
                captured = KeyTable.name(forKeyCode: Int(event.keyCode))
            case .flagsChanged:
                captured = KeyTable.name(forKeyCode: Int(event.keyCode))
            case .scrollWheel:
                if abs(event.scrollingDeltaY) < 1 { return event }
                captured = event.scrollingDeltaY > 0 ? "scroll_up" : "scroll_down"
            default:
                return event
            }
            if let captured {
                value = captured
                stopRecording()
                return nil
            }
            return event
        }
    }

    private func stopRecording() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
