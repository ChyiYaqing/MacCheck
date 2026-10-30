import SwiftUI

/// 侧边栏：概览 + 系统检测 + 硬件测试三段分组，每行显示 SF Symbol 与状态圆点。
struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var ios: IOSDeviceModel

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $model.selection) {
                row(.overview)
                row(.history)
                row(.settings)

                Section(L("系统检测", "System Checks")) {
                    ForEach(SidebarItem.autoCategories) { row($0) }
                    row(.aiModels)
                }

                Section(L("硬件测试", "Hardware Tests")) {
                    ForEach(SidebarItem.interactiveTests) { row($0) }
                }

                if ios.isToolInstalled {
                    deviceSection("iPhone", devices: ios.iPhones)
                    deviceSection("iPad", devices: ios.iPads)
                    deviceSection("Apple Watch", devices: ios.watches,
                                  empty: L("连接配对的 iPhone 后显示", "Connect its paired iPhone"))
                } else {
                    Section("iPhone / iPad") { row(.iosSetup) }
                }
            }
            .listStyle(.sidebar)

            rescanBar
                .fixedSize(horizontal: false, vertical: true)
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
    }

    private func row(_ item: SidebarItem) -> some View {
        Label {
            HStack {
                Text(item.title)
                Spacer()
                if let status = model.status(for: item) {
                    StatusDot(status: status)
                } else if item.isInteractive {
                    Image(systemName: "circle.dashed")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
            }
        } icon: {
            Image(systemName: item.icon)
        }
        .tag(item)
    }

    private func deviceSection(_ title: String, devices: [IOSDevice], empty: String = L("未连接", "Not connected")) -> some View {
        Section(title) {
            if devices.isEmpty {
                Text(empty)
                    .font(DS.Font.caption)
                    .foregroundStyle(.tertiary)
                    .selectionDisabled()
            }
            ForEach(devices) { deviceRow($0) }
        }
    }

    /// 设备行：用户给设备起的名字 + 机型与系统版本，右侧为检测状态。同时连接多台时逐台列出。
    private func deviceRow(_ device: IOSDevice) -> some View {
        Label {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(device.summary.name).lineLimit(1)
                    Text(device.summary.subtitle)
                        .font(DS.Font.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                switch device.phase {
                case .scanning:
                    ProgressView().controlSize(.mini)
                case .untrusted:
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                        .help(L("等待在设备上点「信任」", "Waiting for Trust on the device"))
                case .ready:
                    if let status = device.status { StatusDot(status: status) }
                }
            }
        } icon: {
            Image(systemName: device.summary.symbolName)
        }
        .help(device.summary.udid)
        .tag(SidebarItem.iosDevice(device.id))
    }

    private var rescanBar: some View {
        VStack(spacing: 0) {
            DS.Divider()
            HStack(spacing: DS.Spacing.sm) {
                if model.isScanning {
                    ProgressView().controlSize(.small)
                    Text(L("正在扫描…", "Scanning…")).font(DS.Font.caption).foregroundStyle(.secondary)
                } else {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green).font(.system(size: 12))
                    Text(L("已完成系统扫描", "System scan complete")).font(DS.Font.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await model.rescan() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(model.isScanning)
                .help(L("重新扫描", "Rescan"))
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
        }
    }
}
