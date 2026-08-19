import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 16) {
                    modes
                    HStack(alignment: .top, spacing: 16) {
                        noise
                        equalizer
                    }
                    immersive
                    if let message = model.errorMessage { error(message) }
                }
                .padding(24)
            }
            footer
        }
        .background(Studio.canvas)
        .foregroundStyle(Studio.ink)
        .tint(Studio.ink)
        .frame(minWidth: 720, minHeight: 650)
        .task {
            if model.devices.isEmpty && !model.isRefreshing { model.refreshDevices() }
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("BOSE CONTROL").font(.system(size: 11, weight: .bold)).tracking(1.8)
                Text(model.status).font(.system(size: 12)).foregroundStyle(Studio.secondary)
            }
            Spacer()
            if let battery = model.battery {
                HStack(spacing: 6) {
                    Image(systemName: "battery.\(battery >= 75 ? "100" : battery >= 50 ? "75" : battery >= 25 ? "50" : "25")")
                    Text("\(battery)%").font(.system(size: 12, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(Studio.secondary)
            }
            Menu {
                if model.devices.isEmpty { Text("No paired Bose headset found") }
                ForEach(model.devices) { device in
                    Button { model.select(device) } label: {
                        Text("\(device.name)\(device.connected ? " • connected" : "")")
                    }
                }
                Divider()
                Button("Refresh devices") { model.refreshDevices() }
            } label: {
                HStack(spacing: 8) {
                    Circle().fill(model.selectedDevice?.connected == true ? Studio.success : Studio.tertiary)
                        .frame(width: 7, height: 7)
                    Text(model.selectedDevice?.name ?? "Select headset")
                        .lineLimit(1).frame(maxWidth: 230)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12).frame(height: 34)
                .background(Studio.inset)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Studio.hairline))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 24).frame(height: 64)
        .overlay(alignment: .bottom) { Rectangle().fill(Studio.hairline).frame(height: 1) }
    }

    private var modes: some View {
        Panel {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    sectionTitle("Mode", detail: "Choose how the world around you should sound")
                    Spacer()
                    if model.settings.mode == nil {
                        Text("MANUAL")
                            .font(.system(size: 9, weight: .bold)).tracking(1.2)
                            .foregroundStyle(Studio.secondary)
                            .padding(.horizontal, 9).frame(height: 24)
                            .background(Studio.inset)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Studio.hairline))
                    }
                }
                HStack(spacing: 10) {
                    ForEach(ListeningMode.allCases) { mode in
                        ModeButton(title: mode.rawValue, selected: model.settings.mode == mode,
                                   enabled: model.selectedDevice?.model != .qc45 || mode == .quiet || mode == .aware) {
                            model.selectMode(mode)
                        }
                    }
                }
            }
        }
    }

    private var noise: some View {
        Panel {
            VStack(alignment: .leading, spacing: 17) {
                HStack {
                    sectionTitle("Noise control", detail: "0 ambient · 10 quiet")
                    Spacer()
                    MonochromeSwitch(isOn: Binding(
                        get: { model.settings.noiseEnabled },
                        set: { model.setNoiseEnabled($0) }
                    ))
                    .disabled(model.selectedDevice?.model == .qc45)
                    .opacity(model.selectedDevice?.model == .qc45 ? 0.3 : 1)
                }
                ZStack {
                    Circle().trim(from: 0.12, to: 0.88)
                        .stroke(Studio.hairline, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(90))
                    Circle().trim(from: 0.12, to: 0.12 + 0.76 * Double(model.settings.noiseLevel) / 10)
                        .stroke(Studio.ink, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(90))
                    VStack(spacing: 0) {
                        Text("\(model.settings.noiseLevel)").font(.system(size: 36, weight: .medium, design: .rounded))
                        Text("level").font(.system(size: 11, weight: .medium)).foregroundStyle(Studio.tertiary)
                    }
                }
                .frame(width: 132, height: 132).frame(maxWidth: .infinity)
                NoiseLevelSlider(
                    value: Binding(
                        get: { model.settings.noiseLevel },
                        set: { model.setNoiseLevel($0) }
                    ),
                    enabled: model.settings.noiseEnabled && model.selectedDevice?.model != .qc45
                )
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    private var equalizer: some View {
        Panel {
            VStack(alignment: .leading, spacing: 18) {
                sectionTitle("Equalizer", detail: "Shape the character of your sound")
                LevelSlider(label: "Bass", value: equalizerBinding(.bass), range: -10...10)
                LevelSlider(label: "Mid", value: equalizerBinding(.mid), range: -10...10)
                LevelSlider(label: "Treble", value: equalizerBinding(.treble), range: -10...10)
                Button("Reset") { model.resetEqualizer() }
                .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(Studio.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    private var immersive: some View {
        Panel {
            HStack {
                sectionTitle("Immersive audio", detail: "Spatial soundstage for QC Ultra")
                Spacer()
                ImmersiveSelector(selection: Binding(
                    get: { model.settings.immersive },
                    set: { model.setImmersive($0) }
                ), enabled: model.selectedDevice?.model != .qc45)
            }
        }
    }

    private func sectionTitle(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(detail).font(.system(size: 11)).foregroundStyle(Studio.tertiary)
        }
    }

    private func equalizerBinding(_ band: EqualizerBand) -> Binding<Int> {
        Binding(
            get: {
                switch band {
                case .bass: model.settings.bass
                case .mid: model.settings.mid
                case .treble: model.settings.treble
                }
            },
            set: { model.setEqualizer(band, value: $0) }
        )
    }

    private func error(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle").padding(.top, 1)
            Text(message).font(.system(size: 12)).textSelection(.enabled)
            Spacer()
            Button { model.errorMessage = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
        }
        .foregroundStyle(Studio.error).padding(14)
        .background(Studio.error.opacity(0.055)).clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 8) {
                if model.isSyncing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: model.errorMessage == nil ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(model.errorMessage == nil ? Studio.success : Studio.error)
                }
                Text(model.selectedDevice == nil ? "Select a headset to start syncing" : model.status)
                    .font(.system(size: 12, weight: .medium))
            }
            Spacer()
            Text("Changes sync automatically")
                .font(.system(size: 11)).foregroundStyle(Studio.tertiary)
        }
        .padding(.horizontal, 24).frame(height: 62)
        .overlay(alignment: .top) { Rectangle().fill(Studio.hairline).frame(height: 1) }
    }
}
