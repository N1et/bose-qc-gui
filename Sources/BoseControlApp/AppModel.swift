import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var devices: [BoseDevice] = []
    @Published var selectedDevice: BoseDevice?
    @Published var settings = HeadphoneSettings()
    @Published var battery: Int?
    @Published var isRefreshing = false
    @Published var isSyncing = false
    @Published var status = "Looking for paired headsets…"
    @Published var errorMessage: String?

    private let defaults = UserDefaults.standard
    private var pendingSync: Task<Void, Never>?
    private var settingsRevision = 0

    init() {
        if let data = defaults.data(forKey: "headphoneSettings"),
           let saved = try? JSONDecoder().decode(HeadphoneSettings.self, from: data) {
            settings = saved
        }
    }

    func refreshDevices() {
        guard !isRefreshing else { return }
        isRefreshing = true
        errorMessage = nil
        Task {
            do {
                let found = try await Task.detached { try BluetoothBridge().pairedDevices() }.value
                let bose = found.filter {
                    let name = $0.name.lowercased()
                    return name.contains("bose") || name.contains("quietcomfort") || name.contains("qc ultra")
                }
                devices = bose
                let savedAddress = defaults.string(forKey: "selectedDeviceAddress")
                selectedDevice = bose.first(where: { $0.address == savedAddress })
                    ?? bose.first(where: \BoseDevice.connected)
                    ?? bose.first
                status = bose.isEmpty ? "No paired Bose headset found" : "Ready to control"
                isRefreshing = false
                if selectedDevice != nil { readBattery() }
            } catch {
                isRefreshing = false
                status = "Bluetooth unavailable"
                errorMessage = error.localizedDescription
            }
        }
    }

    func select(_ device: BoseDevice) {
        selectedDevice = device
        defaults.set(device.address, forKey: "selectedDeviceAddress")
        battery = nil
        readBattery()
        queueSync(afterMilliseconds: 150)
    }

    func selectMode(_ mode: ListeningMode) {
        settings.applyPreset(mode)
        queueSync(afterMilliseconds: 150)
    }

    func setNoiseEnabled(_ enabled: Bool) {
        settings.mode = nil
        settings.noiseEnabled = enabled
        queueSync(afterMilliseconds: 150)
    }

    func setNoiseLevel(_ level: Int) {
        settings.mode = nil
        settings.noiseLevel = level
        queueSync(afterMilliseconds: 550)
    }

    func setImmersive(_ immersive: ImmersiveMode) {
        settings.mode = nil
        settings.immersive = immersive
        queueSync(afterMilliseconds: 150)
    }

    func setEqualizer(_ band: EqualizerBand, value: Int) {
        switch band {
        case .bass: settings.bass = value
        case .mid: settings.mid = value
        case .treble: settings.treble = value
        }
        queueSync(afterMilliseconds: 550)
    }

    func resetEqualizer() {
        settings.bass = 0
        settings.mid = 0
        settings.treble = 0
        queueSync(afterMilliseconds: 150)
    }

    private func queueSync(afterMilliseconds delay: UInt64) {
        settingsRevision += 1
        let targetRevision = settingsRevision
        pendingSync?.cancel()
        guard let device = selectedDevice else {
            status = "Select a headset to start syncing"
            return
        }
        status = "Waiting to sync…"
        pendingSync = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay * 1_000_000)
            guard !Task.isCancelled, let self else { return }
            self.pendingSync = nil
            await self.sync(device: device, revision: targetRevision)
        }
    }

    private func sync(device: BoseDevice, revision: Int) async {
        if isSyncing {
            pendingSync = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled, let self else { return }
                self.pendingSync = nil
                await self.sync(device: device, revision: revision)
            }
            return
        }

        let requested = settings
        isSyncing = true
        errorMessage = nil
        status = "Syncing with headset…"
        do {
            try await Task.detached { try BMAPClient().apply(requested, to: device) }.value
            defaults.set(try? JSONEncoder().encode(requested), forKey: "headphoneSettings")
            isSyncing = false
            status = settingsRevision == revision ? "Up to date" : "Waiting to sync…"
        } catch {
            isSyncing = false
            status = "Sync paused"
            errorMessage = error.localizedDescription
        }
    }

    func readBattery() {
        guard let device = selectedDevice else { return }
        Task {
            do {
                battery = try await Task.detached { try BMAPClient().battery(of: device) }.value
            } catch {
                battery = nil
            }
        }
    }
}
