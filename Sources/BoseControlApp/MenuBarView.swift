import SwiftUI
import AppKit

struct MenuBarView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            deviceHeader
            Divider()
            modeSection
            noiseSection
            if model.selectedDevice?.model != .qc45 {
                immersiveSection
            }
            if let error = model.errorMessage {
                errorRow(error)
            }
            Divider()
            footer
        }
        .frame(width: MenuBarLayout.contentWidth, alignment: .leading)
        .padding(.horizontal, MenuBarLayout.horizontalPadding)
        .padding(.vertical, MenuBarLayout.verticalPadding)
        .tint(.accentColor)
        .modifier(MenuPanelSurface())
        .task {
            if model.devices.isEmpty && !model.isRefreshing {
                model.refreshDevices()
            }
        }
    }

    private var deviceHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "headphones")
                .font(.system(size: 16, weight: .medium))
                .frame(width: 32, height: 32)
                .background(.quaternary, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Menu {
                    if model.devices.isEmpty {
                        Text("No paired headset found")
                    }
                    ForEach(model.devices) { device in
                        Button {
                            model.select(device)
                        } label: {
                            if model.selectedDevice?.id == device.id {
                                Label(device.name, systemImage: "checkmark")
                            } else {
                                Text(device.name)
                            }
                        }
                    }
                    Divider()
                    Button("Refresh Devices", systemImage: "arrow.clockwise") {
                        model.refreshDevices()
                    }
                } label: {
                    Text(model.selectedDevice?.name ?? "Select Headset")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 5) {
                    Circle()
                        .fill(model.errorMessage == nil ? Color.green : Color.red)
                        .frame(width: 6, height: 6)
                    Text(model.status)
                        .lineLimit(1)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 8)

            if model.isSyncing || model.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            } else if let battery = model.battery {
                Label("\(battery)%", systemImage: batterySymbol(battery))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }
        }
    }

    private var modeSection: some View {
        ControlSection(title: "Listening Mode", value: model.settings.mode?.rawValue ?? "Manual") {
            Picker("Listening Mode", selection: Binding<ListeningMode?>(
                get: { model.settings.mode },
                set: { mode in
                    if let mode { model.selectMode(mode) }
                }
            )) {
                ForEach(ListeningMode.allCases) { mode in
                    let enabled = model.selectedDevice?.model != .qc45 || mode == .quiet || mode == .aware
                    Text(mode.rawValue)
                        .tag(Optional(mode))
                        .disabled(!enabled)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.large)
            .frame(width: MenuBarLayout.contentWidth)
        }
    }

    private var noiseSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text("Noise Control")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(model.settings.noiseEnabled ? "Level \(model.settings.noiseLevel)" : "Off")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Toggle("Noise Control", isOn: Binding(
                    get: { model.settings.noiseEnabled },
                    set: { model.setNoiseEnabled($0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(model.selectedDevice?.model == .qc45)
            }

            Slider(
                value: Binding(
                    get: { Double(model.settings.noiseLevel) },
                    set: { model.setNoiseLevel(Int($0.rounded())) }
                ),
                in: 0...10,
                step: 1
            ) {
                Text("Noise Control Level")
            } minimumValueLabel: {
                Image(systemName: "ear")
            } maximumValueLabel: {
                Image(systemName: "speaker.slash")
            }
            .symbolRenderingMode(.hierarchical)
            .labelsHidden()
            .disabled(!model.settings.noiseEnabled || model.selectedDevice?.model == .qc45)
        }
    }

    private var immersiveSection: some View {
        ControlSection(title: "Immersive Audio", value: model.settings.immersive.rawValue) {
            Picker("Immersive Audio", selection: Binding(
                get: { model.settings.immersive },
                set: { model.setImmersive($0) }
            )) {
                ForEach(ImmersiveMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.large)
            .frame(width: MenuBarLayout.contentWidth)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                openWindow(id: "main")
                NSApplication.shared.activate(ignoringOtherApps: true)
            } label: {
                Label("Open Bose Control…", systemImage: "macwindow")
            }
            .buttonStyle(.borderless)

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .font(.system(size: 11, weight: .medium))
    }

    private func errorRow(_ text: String) -> some View {
        Label {
            Text(text).lineLimit(3)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.system(size: 10))
        .foregroundStyle(.red)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func batterySymbol(_ value: Int) -> String {
        "battery.\(value >= 75 ? "100" : value >= 50 ? "75" : value >= 25 ? "50" : "25")"
    }
}

private struct ControlSection<Content: View>: View {
    let title: String
    let value: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(value)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum MenuBarLayout {
    static let contentWidth: CGFloat = 336
    static let horizontalPadding: CGFloat = 22
    static let verticalPadding: CGFloat = 20
}

private struct MenuPanelSurface: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}
