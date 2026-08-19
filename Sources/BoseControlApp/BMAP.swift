import Foundation
import BoseBluetoothBridge

enum BMAPOperator: UInt8 {
    case set = 0, get = 1, setGet = 2, status = 3
    case error = 4, start = 5, result = 6, processing = 7
}

struct BMAPFrame: Equatable {
    let functionBlock: UInt8
    let function: UInt8
    let operation: BMAPOperator
    let payload: [UInt8]

    func encoded() throws -> [UInt8] {
        guard payload.count <= 255 else {
            throw BoseError.protocolError("The BMAP payload exceeds 255 bytes.")
        }
        return [functionBlock, function, operation.rawValue, UInt8(payload.count)] + payload
    }

    static func parse(_ bytes: [UInt8]) throws -> [BMAPFrame] {
        var frames: [BMAPFrame] = []
        var offset = 0
        while offset < bytes.count {
            guard bytes.count - offset >= 4 else {
                throw BoseError.protocolError("Partial BMAP response.")
            }
            let length = Int(bytes[offset + 3])
            let end = offset + 4 + length
            guard end <= bytes.count else {
                throw BoseError.protocolError("Truncated BMAP payload.")
            }
            guard let operation = BMAPOperator(rawValue: bytes[offset + 2] & 0x0f) else {
                throw BoseError.protocolError("Unknown BMAP operator.")
            }
            frames.append(BMAPFrame(
                functionBlock: bytes[offset],
                function: bytes[offset + 1],
                operation: operation,
                payload: Array(bytes[(offset + 4)..<end])
            ))
            offset = end
        }
        return frames
    }
}

struct BluetoothBridge {
    func pairedDevices() throws -> [BoseDevice] {
        var output = [CChar](repeating: 0, count: 65_536)
        var error = [CChar](repeating: 0, count: 512)
        let result = bose_list_paired_devices_json(&output, UInt32(output.count), &error, UInt16(error.count))
        guard result >= 0 else { throw BoseError.bluetooth(String(cString: error)) }
        let data = Data(bytes: output, count: Int(result))
        return try JSONDecoder().decode([BoseDevice].self, from: data)
    }

    func transact(address: String, channel: UInt8, frame: [UInt8]) throws -> [UInt8] {
        var request = frame
        var response = [UInt8](repeating: 0, count: 4_096)
        var responseLength: UInt16 = 0
        var error = [CChar](repeating: 0, count: 512)
        let result = address.withCString { addressPointer in
            bose_rfcomm_send_recv(addressPointer, channel, &request, UInt16(request.count),
                                  &response, UInt16(response.count), &responseLength, 8_000,
                                  &error, UInt16(error.count))
        }
        guard result == 0 else { throw BoseError.bluetooth(String(cString: error)) }
        return Array(response.prefix(Int(responseLength)))
    }

    func resolveChannel(address: String, fallback: UInt8) throws -> UInt8 {
        var error = [CChar](repeating: 0, count: 512)
        let result = address.withCString {
            bose_resolve_rfcomm_channel($0, fallback, &error, UInt16(error.count))
        }
        guard result > 0, result <= Int(UInt8.max) else {
            throw BoseError.bluetooth(String(cString: error))
        }
        return UInt8(result)
    }

    func transactBatch(address: String, channel: UInt8, frames: [[UInt8]],
                       delays: [UInt32]) throws -> [UInt8] {
        precondition(frames.count == delays.count)
        var flat = frames.flatMap { $0 }
        var lengths = frames.map { UInt16($0.count) }
        var mutableDelays = delays
        var response = [UInt8](repeating: 0, count: 8_192)
        var responseLength: UInt16 = 0
        var error = [CChar](repeating: 0, count: 512)
        let result = address.withCString { addressPointer in
            bose_rfcomm_multi_send_recv(addressPointer, channel, &flat, &lengths, &mutableDelays,
                                        Int32(frames.count), &response, UInt16(response.count),
                                        &responseLength, 8_000, &error, UInt16(error.count))
        }
        guard result == 0 else { throw BoseError.bluetooth(String(cString: error)) }
        return Array(response.prefix(Int(responseLength)))
    }
}

struct BMAPClient {
    private let bridge = BluetoothBridge()

    func apply(_ settings: HeadphoneSettings, to device: BoseDevice) throws {
        let fallback: UInt8 = device.model == .qc45 ? 9 : 2
        let channel = try channel(for: device, fallback: fallback)
        var requests: [(BMAPFrame, Set<BMAPOperator>, UInt32)] = []

        if let mode = settings.mode {
            let modeIndex = try mode.index(for: device.model)
            requests.append(
                (.init(functionBlock: 31, function: 3, operation: .start, payload: [modeIndex, 0]),
                 device.model == .qc45 ? [.processing, .status, .result] : [.status, .result], 750)
            )
        }

        if device.model == .qcUltra2 {
            let cnc = UInt8(10 - min(max(settings.noiseLevel, 0), 10))
            requests.append((.init(functionBlock: 31, function: 10, operation: .setGet,
                                   payload: [cnc, 0, settings.immersive.bmapValue, 0,
                                             settings.noiseEnabled ? 1 : 0]),
                             [.status, .result], 250))
        }

        for (band, value) in [(0, settings.bass), (1, settings.mid), (2, settings.treble)] {
            let signed = UInt8(bitPattern: Int8(min(max(value, -10), 10)))
            requests.append((.init(functionBlock: 1, function: 7, operation: .setGet,
                                   payload: [signed, UInt8(band)]), [.status, .result], 250))
        }
        requests[requests.count - 1].2 = 0

        let responseBytes = try bridge.transactBatch(
            address: device.address,
            channel: channel,
            frames: try requests.map { try $0.0.encoded() },
            delays: requests.map(\.2)
        )
        let responses = try BMAPFrame.parse(responseBytes)
        try validateBatch(requests: requests, responses: responses)
    }

    private func validateBatch(requests: [(BMAPFrame, Set<BMAPOperator>, UInt32)],
                               responses: [BMAPFrame]) throws {
        if let error = responses.first(where: { $0.operation == .error }) {
            throw BoseError.protocolError("The headset rejected [\(error.functionBlock).\(error.function)] (BMAP error \(error.payload.first ?? 0)).")
        }
        for (request, accepted, _) in requests {
            guard responses.contains(where: {
                $0.functionBlock == request.functionBlock && $0.function == request.function &&
                accepted.contains($0.operation)
            }) else {
                throw BoseError.protocolError("No confirmation received for [\(request.functionBlock).\(request.function)].")
            }
        }
    }

    func battery(of device: BoseDevice) throws -> Int {
        let fallback: UInt8 = device.model == .qc45 ? 9 : 2
        let channel = try channel(for: device, fallback: fallback)
        let response = try request(.init(functionBlock: 2, function: 2, operation: .get, payload: []),
                                   to: device, channel: channel, accepted: [.status, .result])
        guard let value = response.payload.first else {
            throw BoseError.protocolError("The battery response was empty.")
        }
        return Int(value)
    }

    private func channel(for device: BoseDevice, fallback: UInt8) throws -> UInt8 {
        // These model channels were verified on hardware. Some SDP records on
        // the QC Ultra 2 also contain the Bose UUID but point to channel 14,
        // which rejects BMAP connections.
        switch device.model {
        case .qcUltra2, .qc45: return fallback
        }
    }

    private func send(_ frame: BMAPFrame, to device: BoseDevice, channel: UInt8,
                      accepted: Set<BMAPOperator>) throws {
        _ = try request(frame, to: device, channel: channel, accepted: accepted)
    }

    private func request(_ frame: BMAPFrame, to device: BoseDevice, channel: UInt8,
                         accepted: Set<BMAPOperator>) throws -> BMAPFrame {
        let bytes = try bridge.transact(address: device.address, channel: channel, frame: frame.encoded())
        let frames = try BMAPFrame.parse(bytes)
        let matching = frames.filter {
            $0.functionBlock == frame.functionBlock && $0.function == frame.function
        }
        if let error = matching.first(where: { $0.operation == .error }) {
            let code = error.payload.first ?? 0
            throw BoseError.protocolError("The headset rejected [\(frame.functionBlock).\(frame.function)] (BMAP error \(code)).")
        }
        guard let response = matching.first(where: { accepted.contains($0.operation) }) else {
            throw BoseError.protocolError("Unexpected response for [\(frame.functionBlock).\(frame.function)].")
        }
        return response
    }
}
