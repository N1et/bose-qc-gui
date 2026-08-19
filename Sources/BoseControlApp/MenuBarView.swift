import SwiftUI
import AppKit

struct MenuBarView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            separator
            modes
            noise
            if model.selectedDevice?.model != .qc45 { immersive }
            if let error = model.errorMessage { errorRow(error) }
            separator
            actions
        }
        .padding(16)
        .frame(width: 340)
        .background(Studio.canvas)
        .foregroundStyle(Studio.ink)
        .tint(Studio.ink)
        .task {
            if model.devices.isEmpty && !model.isRefreshing { model.refreshDevices() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("BOSE CONTROL")
                        .font(.system(size: 10, weight: .bold)).tracking(1.6)
                    Text(model.status)
                        .font(.system(size: 11)).foregroundStyle(Studio.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if model.isSyncing {
                    ProgressView().controlSize(.small)
                } else if let battery = model.battery {
                    HStack(spacing: 5) {
                        Image(systemName: batterySymbol(battery))
                        Text("\(battery)%")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(Studio.secondary)
                }
            }

            Menu {
                if model.devices.isEmpty { Text("No paired Bose headset found") }
                ForEach(model.devices) { device in
                    Button { model.select(device) } label: {
                        if model.selectedDevice?.id == device.id {
                            Label(device.name, systemImage: "checkmark")
                        } else {
                            Text(device.name)
                        }
                    }
                }
                Divider()
                Button("Refresh devices") { model.refreshDevices() }
            } label: {
                HStack(spacing: 7) {
                    Circle()
                        .fill(model.errorMessage == nil ? Studio.success : Studio.error)
                        .frame(width: 7, height: 7)
                    Text(model.selectedDevice?.name ?? "Select headset")
                        .font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(Studio.secondary)
                }
                .padding(.horizontal, 10).frame(height: 32)
                .background(Studio.inset)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Studio.hairline))
            }
            .menuStyle(.borderlessButton)
        }
    }

    private var modes: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                quickLabel("MODE")
                Spacer()
                if model.settings.mode == nil {
                    Text("MANUAL").font(.system(size: 8, weight: .bold)).tracking(1)
                        .foregroundStyle(Studio.secondary)
                }
            }
            LazyVGrid(columns: columns, spacing: 7) {
                ForEach(ListeningMode.allCases) { mode in
                    let enabled = model.selectedDevice?.model != .qc45 || mode == .quiet || mode == .aware
                    Button { model.selectMode(mode) } label: {
                        Text(mode.rawValue)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(model.settings.mode == mode ? Color.white : Studio.ink)
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .background(model.settings.mode == mode ? Studio.ink : Studio.inset)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(
                                model.settings.mode == mode ? Color.clear : Studio.hairline
                            ))
                    }
                    .buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.3)
                }
            }
        }
    }

    private var noise: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                quickLabel("NOISE CONTROL")
                Spacer()
                Text("\(model.settings.noiseLevel)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Studio.secondary)
                MonochromeSwitch(isOn: Binding(
                    get: { model.settings.noiseEnabled },
                    set: { model.setNoiseEnabled($0) }
                ))
                .scaleEffect(0.84)
                .disabled(model.selectedDevice?.model == .qc45)
            }
            NoiseLevelSlider(
                value: Binding(
                    get: { model.settings.noiseLevel },
                    set: { model.setNoiseLevel($0) }
                ),
                enabled: model.settings.noiseEnabled && model.selectedDevice?.model != .qc45
            )
        }
    }

    private var immersive: some View {
        VStack(alignment: .leading, spacing: 9) {
            quickLabel("IMMERSIVE AUDIO")
            ImmersiveSelector(
                selection: Binding(
                    get: { model.settings.immersive },
                    set: { model.setImmersive($0) }
                ),
                enabled: true,
                width: 308
            )
        }
    }

    private var actions: some View {
        HStack {
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Studio.secondary)
            Spacer()
            Button {
                openWindow(id: "main")
                NSApplication.shared.activate(ignoringOtherApps: true)
            } label: {
                HStack(spacing: 6) {
                    Text("Open Bose Control")
                    Image(systemName: "arrow.up.right")
                }
                .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
        }
    }

    private var separator: some View {
        Rectangle().fill(Studio.hairline).frame(height: 1)
    }

    private func quickLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 9, weight: .bold)).tracking(1.2)
            .foregroundStyle(Studio.secondary)
    }

    private func errorRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "exclamationmark.circle").padding(.top, 1)
            Text(text).font(.system(size: 10)).lineLimit(3)
        }
        .foregroundStyle(Studio.error)
    }

    private func batterySymbol(_ value: Int) -> String {
        "battery.\(value >= 75 ? "100" : value >= 50 ? "75" : value >= 25 ? "50" : "25")"
    }
}
