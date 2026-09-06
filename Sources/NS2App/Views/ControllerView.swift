import SwiftUI
import NS2Core

struct ControllerView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 14) {
            GroupBox("Состояние") {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow {
                        Text("USB").foregroundStyle(.secondary)
                        HStack { StatusDot(ok: model.usbPresent); Text(model.usbPresent ? "подключён" : "не подключён") }
                    }
                    GridRow {
                        Text("HID").foregroundStyle(.secondary)
                        HStack {
                            StatusDot(ok: model.hidAttached && model.reportsPerSecond > 0)
                            Text(model.hidAttached ? "активен, \(model.reportsPerSecond) отчётов/с" : "нет отчётов, нужно пробуждение")
                        }
                    }
                    GridRow {
                        Text("Событие").foregroundStyle(.secondary)
                        Text(model.lastEvent)
                    }
                    GridRow {
                        Text("Калибровка").foregroundStyle(.secondary)
                        Text(calibrationText).font(.system(.caption, design: .monospaced))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }
            HStack(spacing: 12) {
                Button("Разбудить") { model.wakeNow() }.disabled(!model.usbPresent)
                Button("Сбросить") { model.resetController() }.disabled(!model.usbPresent)
                Toggle("Автопробуждение", isOn: $model.autoWakeEnabled).toggleStyle(.switch)
                Spacer()
                Picker("LED игрока", selection: $model.playerLED) {
                    ForEach(1...4, id: \.self) { Text("\($0)").tag($0) }
                }
                .frame(width: 150)
                Button("Применить") { model.applyPlayerLED() }.disabled(!model.usbPresent)
            }
            GroupBox("Ввод (report 0x09)") {
                ControllerVisualizer(state: model.state, calibration: model.calibration)
                    .frame(maxWidth: .infinity, minHeight: 260)
            }
        }
    }

    private var calibrationText: String {
        let l = model.calibration.left
        let r = model.calibration.right
        return "L центр \(l.x.center)/\(l.y.center) ход +\(l.x.rangeAbove)/−\(l.x.rangeBelow)  ·  R центр \(r.x.center)/\(r.y.center) ход +\(r.x.rangeAbove)/−\(r.x.rangeBelow)"
    }
}

struct ControllerVisualizer: View {
    var state: ControllerState
    var calibration: (left: StickCalibration, right: StickCalibration)

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            let unit = min(w / 14, h / 7)
            ZStack {
                RoundedRectangle(cornerRadius: unit * 1.5)
                    .fill(Color.secondary.opacity(0.08))
                    .frame(width: unit * 13, height: unit * 6.4)
                    .position(x: w / 2, y: h * 0.55)

                shoulder("ZL", .zl, x: 0.14, y: 0.08, w: w, h: h, unit: unit)
                shoulder("L", .l, x: 0.14, y: 0.2, w: w, h: h, unit: unit)
                shoulder("ZR", .zr, x: 0.86, y: 0.08, w: w, h: h, unit: unit)
                shoulder("R", .r, x: 0.86, y: 0.2, w: w, h: h, unit: unit)

                stick(raw: state.leftRaw, calibration: calibration.left, pressed: state.isPressed(.leftStick))
                    .frame(width: unit * 2.2, height: unit * 2.2)
                    .position(x: w * 0.2, y: h * 0.47)
                stick(raw: state.rightRaw, calibration: calibration.right, pressed: state.isPressed(.rightStick))
                    .frame(width: unit * 2.2, height: unit * 2.2)
                    .position(x: w * 0.64, y: h * 0.68)

                dpad(x: 0.34, y: 0.72, w: w, h: h, unit: unit)

                face("X", .x, x: 0.8, y: 0.3, w: w, h: h, unit: unit)
                face("Y", .y, x: 0.72, y: 0.45, w: w, h: h, unit: unit)
                face("A", .a, x: 0.88, y: 0.45, w: w, h: h, unit: unit)
                face("B", .b, x: 0.8, y: 0.6, w: w, h: h, unit: unit)

                small("−", .minus, x: 0.41, y: 0.36, w: w, h: h, unit: unit)
                small("+", .plus, x: 0.59, y: 0.36, w: w, h: h, unit: unit)
                small("⊙", .capture, x: 0.41, y: 0.52, w: w, h: h, unit: unit)
                small("⌂", .home, x: 0.59, y: 0.52, w: w, h: h, unit: unit)
                small("C", .c, x: 0.5, y: 0.64, w: w, h: h, unit: unit)

                shoulder("GL", .gl, x: 0.3, y: 0.95, w: w, h: h, unit: unit)
                shoulder("GR", .gr, x: 0.7, y: 0.95, w: w, h: h, unit: unit)
            }
        }
    }

    private func fill(_ pressed: Bool) -> Color {
        pressed ? Color.accentColor : Color.secondary.opacity(0.25)
    }

    private func shoulder(_ label: String, _ button: ProController2Button, x: Double, y: Double, w: Double, h: Double, unit: Double) -> some View {
        Capsule()
            .fill(fill(state.isPressed(button)))
            .frame(width: unit * 2.4, height: unit * 0.7)
            .overlay(Text(label).font(.system(size: unit * 0.4, weight: .semibold)))
            .position(x: w * x, y: h * y)
    }

    private func face(_ label: String, _ button: ProController2Button, x: Double, y: Double, w: Double, h: Double, unit: Double) -> some View {
        Circle()
            .fill(fill(state.isPressed(button)))
            .frame(width: unit * 0.9, height: unit * 0.9)
            .overlay(Text(label).font(.system(size: unit * 0.45, weight: .bold)))
            .position(x: w * x, y: h * y)
    }

    private func small(_ label: String, _ button: ProController2Button, x: Double, y: Double, w: Double, h: Double, unit: Double) -> some View {
        Circle()
            .fill(fill(state.isPressed(button)))
            .frame(width: unit * 0.6, height: unit * 0.6)
            .overlay(Text(label).font(.system(size: unit * 0.32, weight: .semibold)))
            .position(x: w * x, y: h * y)
    }

    private func dpad(x: Double, y: Double, w: Double, h: Double, unit: Double) -> some View {
        let size = unit * 0.6
        let step = unit * 0.62
        return ZStack {
            RoundedRectangle(cornerRadius: 3).fill(fill(state.isPressed(.dpadUp))).frame(width: size, height: size).offset(y: -step)
            RoundedRectangle(cornerRadius: 3).fill(fill(state.isPressed(.dpadDown))).frame(width: size, height: size).offset(y: step)
            RoundedRectangle(cornerRadius: 3).fill(fill(state.isPressed(.dpadLeft))).frame(width: size, height: size).offset(x: -step)
            RoundedRectangle(cornerRadius: 3).fill(fill(state.isPressed(.dpadRight))).frame(width: size, height: size).offset(x: step)
            RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.15)).frame(width: size, height: size)
        }
        .position(x: w * x, y: h * y)
    }

    private func stick(raw: StickRaw, calibration: StickCalibration, pressed: Bool) -> some View {
        let value = calibration.normalize(raw, deadzone: 0.02)
        return GeometryReader { geometry in
            let radius = geometry.size.width / 2
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.4), lineWidth: 1.5)
                Circle().fill(Color.secondary.opacity(0.08))
                Circle()
                    .fill(pressed ? Color.accentColor : Color.primary.opacity(0.7))
                    .frame(width: radius * 0.6, height: radius * 0.6)
                    .offset(x: value.x * radius * 0.7, y: -value.y * radius * 0.7)
            }
        }
    }
}
