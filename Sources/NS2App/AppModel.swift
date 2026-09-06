import AppKit
import Foundation
import Observation
import ServiceManagement
import NS2Core

final class InputHub: @unchecked Sendable {
    private let lock = NSLock()
    private var latest = ControllerState.idle
    private var lastRaw: [UInt8] = []
    private var count = 0
    private var _bridge: KBMBridge?

    var bridge: KBMBridge? {
        get { lock.lock(); defer { lock.unlock() }; return _bridge }
        set { lock.lock(); _bridge = newValue; lock.unlock() }
    }

    func push(_ state: ControllerState) {
        lock.lock()
        latest = state
        count += 1
        let bridge = _bridge
        lock.unlock()
        bridge?.handle(state)
    }

    func pushRaw(_ bytes: [UInt8]) {
        lock.lock(); lastRaw = bytes; lock.unlock()
    }

    func snapshot() -> (state: ControllerState, raw: [UInt8], count: Int) {
        lock.lock(); defer { lock.unlock() }
        return (latest, lastRaw, count)
    }
}

@MainActor
@Observable
final class AppModel {
    static let launchAgentLabel = "com.p1rate.ns2controller"
    static let appLogURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/ns2controller-app.log")

    var started = false
    var usbPresent = false
    var hidAttached = false
    var deviceDescription = ""
    var reportsPerSecond = 0
    var state = ControllerState.idle
    var lastRaw: [UInt8] = []
    var calibration: (left: StickCalibration, right: StickCalibration) = (.fallback, .fallback)
    var lastEvent = "—"
    var autoWakeEnabled: Bool {
        didSet { UserDefaults.standard.set(autoWakeEnabled, forKey: "autoWake"); applyAutoWake() }
    }
    var bluetoothEnabled: Bool {
        didSet { UserDefaults.standard.set(bluetoothEnabled, forKey: "bluetooth"); applyBluetooth() }
    }
    var bleStatus: BLEInputSource.Status = .off
    var bleConnected: Bool {
        if case .connected = bleStatus { return true }
        return false
    }
    var inputAvailable: Bool { hidAttached || bleConnected }
    var playerLED: Int {
        didSet { UserDefaults.standard.set(playerLED, forKey: "playerLED"); autoWake?.playerLED = playerLED }
    }

    var profiles: [String] = []
    var selectedProfile: String {
        didSet { UserDefaults.standard.set(selectedProfile, forKey: "profile"); loadProfileForEditing() }
    }
    var editingProfile: KBMProfile?
    var editorMessage: String?
    var editorIsError = false
    var bridgeRunning = false
    var bridgePaused = false
    var bridgeExclusive = false
    var accessibilityTrusted = false

    var steamStatus: SteamIntegration.Status = .steamNotFound
    var steamRunning = false
    var bottles: [String] = []
    var selectedBottle = ""
    var crossOverInstalled = false
    var crossOverBusy = false
    var integrationMessage: String?

    var logLines: [LogLine] = []
    var launchAtLogin = false
    var launchAgentActive = false
    var settingsMessage: String?

    private let hub = InputHub()
    private var input: HIDInputSource?
    private var ble: BLEInputSource?
    private var autoWake: AutoWakeService?
    private var injector: EventInjector?
    private var lastCount = 0
    private var lastCountTime = Date()
    private var logHandle: FileHandle?

    var bleStatusText: String {
        switch bleStatus {
        case .off: return "выключен"
        case .unauthorized: return "нет разрешения: Системные настройки → Конфиденциальность → Bluetooth"
        case .poweredOff: return "Bluetooth выключен"
        case .scanning: return "поиск… зажми кнопку синхронизации на контроллере"
        case let .connecting(name): return "подключение к \(name)"
        case let .probing(name): return "поиск характеристики у \(name)"
        case let .connected(name): return "подключён: \(name)"
        }
    }

    var statusLine: String {
        if bleConnected { return bridgeRunning ? (bridgePaused ? "Мост на паузе (Bluetooth)" : "Мост работает: \(selectedProfile) (Bluetooth)") : "Bluetooth: \(reportsPerSecond) отч/с" }
        if !usbPresent { return bluetoothEnabled ? "Bluetooth: \(bleStatusText)" : "Контроллер не подключён" }
        if !hidAttached { return "Контроллер подключён, HID не активен" }
        return bridgeRunning ? (bridgePaused ? "Мост на паузе" : "Мост работает: \(selectedProfile)") : "Контроллер активен, \(reportsPerSecond) отч/с"
    }

    init() {
        let defaults = UserDefaults.standard
        autoWakeEnabled = defaults.object(forKey: "autoWake") as? Bool ?? true
        bluetoothEnabled = defaults.bool(forKey: "bluetooth")
        playerLED = max(1, min(8, defaults.integer(forKey: "playerLED") == 0 ? 1 : defaults.integer(forKey: "playerLED")))
        selectedProfile = defaults.string(forKey: "profile") ?? "default"
        Log.printToStdout = false
        logLines = Log.recent()
        openLogFile()
        Log.sink = { line in
            Task { @MainActor [weak self] in self?.append(line) }
        }
    }

    func startIfNeeded() {
        guard !started else { return }
        started = true
        Log.info("NS2 Controller app started")
        refreshProfiles()
        refreshStatuses()
        startInput()
        applyAutoWake()
        if let cached = CalibrationStore.load() { calibration = cached }
        applyBluetooth()
        Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                self.refreshFromHub()
            }
        }
        Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                self.refreshStatuses()
            }
        }
    }

    func shutdown() {
        stopBridge()
        autoWake?.stop()
        ble?.stop()
        input?.stop()
        Log.info("NS2 Controller app stopped")
    }

    private func openLogFile() {
        let url = Self.appLogURL
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        logHandle = try? FileHandle(forWritingTo: url)
        logHandle?.seekToEndOfFile()
    }

    private func append(_ line: LogLine) {
        logLines.append(line)
        if logLines.count > 1000 { logLines.removeFirst(logLines.count - 1000) }
        logHandle?.write(Data((line.formatted + "\n").utf8))
    }

    func clearLog() {
        logLines.removeAll()
    }

    private func startInput() {
        let hub = hub
        let source = HIDInputSource(exclusive: false,
                                    onAttach: { description in
                                        Log.info("HID attached: \(description)")
                                        Task { @MainActor [weak self] in
                                            self?.hidAttached = true
                                            self?.deviceDescription = description
                                            self?.readCalibration()
                                        }
                                    },
                                    onDetach: { _ in
                                        Log.info("HID detached")
                                        Task { @MainActor [weak self] in
                                            self?.hidAttached = false
                                            self?.hub.bridge?.releaseAll()
                                        }
                                    },
                                    onState: { hub.push($0) })
        source.onRawReport = { hub.pushRaw($0) }
        do {
            try source.start()
            input = source
        } catch {
            Log.error("HID input failed: \(error)")
        }
    }

    private func refreshFromHub() {
        let snapshot = hub.snapshot()
        state = snapshot.state
        lastRaw = snapshot.raw
        let now = Date()
        let elapsed = now.timeIntervalSince(lastCountTime)
        if elapsed >= 1 {
            reportsPerSecond = Int(Double(snapshot.count - lastCount) / elapsed)
            lastCount = snapshot.count
            lastCountTime = now
            if reportsPerSecond == 0, hidAttached, input?.isAttached == false { hidAttached = false }
        }
        if let bridge = hub.bridge { bridgePaused = bridge.paused }
    }

    func refreshStatuses() {
        let interfaces = IORegistry.findBulkInterfaces()
        usbPresent = !interfaces.isEmpty
        interfaces.forEach { IOObjectRelease($0.service) }
        accessibilityTrusted = EventInjector.isAccessibilityTrusted(prompt: false)
        steamStatus = SteamIntegration.status()
        steamRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: SteamIntegration.steamBundleIdentifier).isEmpty
        bottles = CrossOverIntegration.bottles()
        if selectedBottle.isEmpty || !bottles.contains(selectedBottle) { selectedBottle = bottles.first ?? "" }
        crossOverInstalled = selectedBottle.isEmpty ? false : CrossOverIntegration.isInstalled(bottle: selectedBottle)
        launchAtLogin = SMAppService.mainApp.status == .enabled
        launchAgentActive = Self.launchAgentLoaded()
        refreshProfileList()
    }

    private func readCalibration() {
        Task.detached { [weak self] in
            guard let transport = try? BulkTransport() else { return }
            let calibration = StickCalibration.read(using: Controller(transport: transport))
            transport.close()
            await MainActor.run { self?.calibration = calibration }
        }
    }

    private func applyBluetooth() {
        if bluetoothEnabled {
            guard ble == nil else { return }
            let hub = hub
            let source = BLEInputSource(onStatus: { status in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.bleStatus = status
                    if case .connected = status {} else { self.hub.bridge?.releaseAll() }
                }
            }, onState: { hub.push($0) })
            source.onRawReport = { hub.pushRaw($0) }
            source.start()
            ble = source
        } else {
            ble?.stop()
            ble = nil
            bleStatus = .off
        }
    }

    private func applyAutoWake() {
        if autoWakeEnabled {
            guard autoWake == nil else { return }
            let service = AutoWakeService(playerLED: playerLED)
            service.onEvent = { event in
                Task { @MainActor [weak self] in self?.handle(event) }
            }
            do {
                try service.start()
                autoWake = service
            } catch {
                Log.error("auto-wake failed: \(error)")
            }
        } else {
            autoWake?.stop()
            autoWake = nil
        }
    }

    private func handle(_ event: AutoWakeService.Event) {
        switch event {
        case let .detected(name): lastEvent = "Обнаружен \(name)"
        case let .woke(name, replies, total): lastEvent = "\(name) разбужен (\(replies)/\(total) ответов)"
        case let .failed(name): lastEvent = "Не удалось разбудить \(name)"
        case let .removed(name): lastEvent = "\(name) отключён"
        case .systemWake: lastEvent = "Mac проснулся, переинициализация"
        }
        refreshStatuses()
    }

    func wakeNow() {
        let led = playerLED
        let service = autoWake
        Task.detached {
            if let service {
                service.wakeAll()
            } else {
                guard let transport = try? BulkTransport() else { Log.warn("no controller on USB"); return }
                let controller = Controller(transport: transport)
                controller.wake()
                controller.setPlayerLED(led)
                transport.close()
            }
        }
    }

    func resetController() {
        Task.detached {
            guard let transport = try? BulkTransport() else { return }
            Log.info("resetting controller")
            Controller(transport: transport).reset()
            transport.close()
        }
    }

    func applyPlayerLED() {
        let led = playerLED
        Task.detached {
            guard let transport = try? BulkTransport() else { return }
            Controller(transport: transport).setPlayerLED(led)
            transport.close()
        }
    }

    func setFormat(_ format: WakeUpSequence.InputReportFormat) {
        Task.detached {
            guard let transport = try? BulkTransport() else { return }
            Controller(transport: transport).setInputReportFormat(format)
            transport.close()
        }
    }

    // MARK: - Bridge

    func refreshProfileList() {
        let names = KBMProfile.list()
        if names != profiles { profiles = names }
    }

    func refreshProfiles() {
        profiles = KBMProfile.list()
        if profiles.isEmpty {
            try? KBMProfile.writeTemplate(name: "default")
            profiles = KBMProfile.list()
        }
        if !profiles.contains(selectedProfile) { selectedProfile = profiles.first ?? "default" }
        loadProfileForEditing()
    }

    func loadProfileForEditing() {
        editorMessage = nil
        editingProfile = try? KBMProfile.load(name: selectedProfile)
    }

    func saveEditedProfile() {
        guard let profile = editingProfile else { return }
        do {
            _ = try profile.resolved()
            let url = try KBMProfile.save(profile, name: selectedProfile)
            editorMessage = "Сохранено: \(url.lastPathComponent)"
            editorIsError = false
            if bridgeRunning { stopBridge(); startBridge() }
        } catch {
            editorMessage = "\(error)"
            editorIsError = true
        }
    }

    func createProfile(named rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "/", with: "-")
        guard !name.isEmpty else { return }
        do {
            try KBMProfile.writeTemplate(name: name)
            refreshProfiles()
            selectedProfile = name
        } catch {
            editorMessage = "\(error)"
            editorIsError = true
        }
    }

    func deleteSelectedProfile() {
        guard profiles.count > 1 else { return }
        try? KBMProfile.delete(name: selectedProfile)
        refreshProfiles()
    }

    func startBridge() {
        guard !bridgeRunning else { return }
        accessibilityTrusted = EventInjector.isAccessibilityTrusted(prompt: true)
        guard accessibilityTrusted else {
            editorMessage = "Нужно разрешение Accessibility для NS2 Controller"
            editorIsError = true
            return
        }
        do {
            let profile = try KBMProfile.load(name: selectedProfile).resolved()
            let injector = EventInjector()
            let bridge = KBMBridge(profile: profile, calibration: calibration, injector: injector)
            bridge.onPauseChange = { paused in
                Log.info(paused ? "bridge paused" : "bridge resumed")
                Task { @MainActor in NSSound.beep() }
            }
            self.injector = injector
            hub.bridge = bridge
            bridgeRunning = true
            bridgePaused = false
            editorMessage = nil
            Log.info("bridge started with profile '\(selectedProfile)'")
        } catch {
            editorMessage = "\(error)"
            editorIsError = true
        }
    }

    func stopBridge() {
        guard bridgeRunning else { return }
        hub.bridge?.releaseAll()
        hub.bridge = nil
        injector = nil
        bridgeRunning = false
        bridgePaused = false
        Log.info("bridge stopped")
    }

    func setBridgePaused(_ paused: Bool) {
        hub.bridge?.setPaused(paused)
        bridgePaused = paused
    }

    func requestAccessibility() {
        accessibilityTrusted = EventInjector.isAccessibilityTrusted(prompt: true)
        if !accessibilityTrusted { EventInjector.openAccessibilitySettings() }
    }

    // MARK: - Integrations

    func installSteamMapping() {
        integrationMessage = nil
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: SteamIntegration.steamBundleIdentifier)
        if !running.isEmpty {
            running.forEach { $0.terminate() }
            integrationMessage = "Закрываю Steam…"
            Task { @MainActor [weak self] in
                for _ in 0..<40 {
                    try? await Task.sleep(for: .milliseconds(500))
                    if NSRunningApplication.runningApplications(withBundleIdentifier: SteamIntegration.steamBundleIdentifier).isEmpty { break }
                }
                self?.performSteamInstall(relaunch: true)
            }
        } else {
            performSteamInstall(relaunch: false)
        }
    }

    private func performSteamInstall(relaunch: Bool) {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: SteamIntegration.steamBundleIdentifier).isEmpty else {
            integrationMessage = "Steam не закрылся, попробуй закрыть его вручную"
            return
        }
        do {
            let backup = try SteamIntegration.install()
            integrationMessage = "Маппинг записан в config.vdf (бэкап \(backup.lastPathComponent))"
            if relaunch { NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Steam.app")) }
        } catch {
            integrationMessage = "\(error)"
        }
        refreshStatuses()
    }

    func installCrossOverMapping() {
        guard !selectedBottle.isEmpty else { return }
        integrationMessage = nil
        do {
            _ = try CrossOverIntegration.install(bottle: selectedBottle)
        } catch {
            integrationMessage = "\(error)"
            return
        }
        crossOverBusy = true
        integrationMessage = "Записано в cxbottle.conf, чищу ключ winebus\\map (бутылка поднимается, до минуты)…"
        let bottle = selectedBottle
        CrossOverIntegration.removeWinebusMapKey(bottle: bottle) { ok in
            Task { @MainActor [weak self] in
                self?.crossOverBusy = false
                self?.integrationMessage = ok ? "Готово. Перезапусти бутылку '\(bottle)' и игру." : "Маппинг записан, но wine не запустился; ключ winebus\\map не проверен"
                self?.refreshStatuses()
            }
        }
    }

    // MARK: - Settings

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            settingsMessage = nil
        } catch {
            settingsMessage = "\(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    static func launchAgentLoaded() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", "gui/\(getuid())/\(launchAgentLabel)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    func disableLaunchAgent() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootout", "gui/\(getuid())/\(Self.launchAgentLabel)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        let plist = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(Self.launchAgentLabel).plist")
        try? FileManager.default.removeItem(at: plist)
        settingsMessage = "LaunchAgent выключен и удалён; пробуждение делает приложение"
        Log.info("LaunchAgent \(Self.launchAgentLabel) disabled")
        refreshStatuses()
    }

    func openAppLog() {
        NSWorkspace.shared.open(Self.appLogURL)
    }
}
