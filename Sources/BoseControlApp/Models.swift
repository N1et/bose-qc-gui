import Foundation

struct BoseDevice: Codable, Identifiable, Hashable {
    let name: String
    let address: String
    let connected: Bool
    var id: String { address }

    var model: HeadphoneModel {
        let normalized = name.lowercased()
        if normalized.contains("quietcomfort 45") || normalized.contains("qc45") || normalized.contains("qc 45") {
            return .qc45
        }
        return .qcUltra2
    }
}

enum HeadphoneModel { case qcUltra2, qc45 }

enum EqualizerBand { case bass, mid, treble }

enum ListeningMode: String, CaseIterable, Codable, Identifiable {
    case quiet = "Quiet"
    case aware = "Aware"
    case immersion = "Immersion"
    case cinema = "Cinema"
    var id: Self { self }

    func index(for model: HeadphoneModel) throws -> UInt8 {
        switch (model, self) {
        case (.qc45, .quiet): return 0
        case (.qc45, .aware): return 2
        case (.qc45, _): throw BoseError.unsupported("This mode is not available on the QC45.")
        case (_, .quiet): return 0
        case (_, .aware): return 1
        case (_, .immersion): return 2
        case (_, .cinema): return 3
        }
    }
}

enum ImmersiveMode: String, CaseIterable, Codable, Identifiable {
    case off = "Off"
    case still = "Still"
    case motion = "Motion"
    var id: Self { self }
    var bmapValue: UInt8 {
        switch self { case .off: 0; case .still: 1; case .motion: 2 }
    }
}

struct HeadphoneSettings: Codable, Equatable {
    var mode: ListeningMode? = .quiet
    var noiseEnabled = true
    var noiseLevel = 10
    var immersive: ImmersiveMode = .off
    var bass = 0
    var mid = 0
    var treble = 0

    mutating func applyPreset(_ preset: ListeningMode) {
        mode = preset
        switch preset {
        case .quiet:
            noiseEnabled = true
            noiseLevel = 10
            immersive = .off
        case .aware:
            noiseEnabled = true
            noiseLevel = 0
            immersive = .off
        case .immersion:
            noiseEnabled = true
            noiseLevel = 10
            immersive = .motion
        case .cinema:
            noiseEnabled = true
            noiseLevel = 10
            immersive = .still
        }
    }
}

enum BoseError: LocalizedError {
    case bluetooth(String)
    case protocolError(String)
    case unsupported(String)
    case noDevice

    var errorDescription: String? {
        switch self {
        case .bluetooth(let text), .protocolError(let text), .unsupported(let text): text
        case .noDevice: "Select a Bose headset before applying changes."
        }
    }
}
