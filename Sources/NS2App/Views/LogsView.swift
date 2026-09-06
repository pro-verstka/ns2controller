import SwiftUI
import NS2Core

struct LogsView: View {
    @Environment(AppModel.self) private var model
    @State private var verbose = Log.verbose
    @State private var descriptor: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Toggle("Подробный лог", isOn: $verbose).onChange(of: verbose) { _, value in Log.verbose = value }
                Spacer()
                Button("Дескриптор устройства") { descriptor = HIDMonitor.devices().first.map(HIDMonitor.describe) ?? "HID-устройство не найдено" }
                Button("Открыть файл лога") { model.openAppLog() }
                Button("Очистить") { model.clearLog() }
            }
            ScrollViewReader { proxy in
                List(model.logLines) { line in
                    Text(line.formatted)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(color(for: line.level))
                        .id(line.id)
                }
                .onChange(of: model.logLines.count) { _, _ in
                    if let last = model.logLines.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            GroupBox("Диагностика") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.deviceDescription.isEmpty ? "HID-устройство не подключено" : model.deviceDescription)
                    Text(model.lastRaw.isEmpty ? "отчётов нет" : "последний отчёт: " + model.lastRaw.hexString)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }
        }
        .sheet(item: Binding(get: { descriptor.map(DescriptorText.init) }, set: { descriptor = $0?.text })) { item in
            VStack(alignment: .leading) {
                ScrollView { Text(item.text).font(.system(.caption, design: .monospaced)).textSelection(.enabled).padding() }
                HStack { Spacer(); Button("Закрыть") { descriptor = nil } }.padding()
            }
            .frame(width: 720, height: 480)
        }
    }

    private func color(for level: String) -> Color {
        switch level {
        case "ERROR": return .red
        case "WARN": return .orange
        case "DEBUG": return .secondary
        default: return .primary
        }
    }
}

private struct DescriptorText: Identifiable {
    var text: String
    var id: String { text }
}
