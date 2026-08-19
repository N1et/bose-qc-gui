import XCTest
@testable import BoseControlApp

final class BMAPTests: XCTestCase {
    func testBuildsLiveAudioPacket() throws {
        let frame = BMAPFrame(functionBlock: 31, function: 10, operation: .setGet,
                              payload: [0, 0, 2, 0, 1])
        XCTAssertEqual(try frame.encoded(), [31, 10, 2, 5, 0, 0, 2, 0, 1])
    }

    func testParsesRoutedOperatorAndMultipleFrames() throws {
        let frames = try BMAPFrame.parse([31, 3, 0x46, 1, 0, 2, 2, 3, 1, 90])
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames[0].operation, .result)
        XCTAssertEqual(frames[1].payload, [90])
    }

    func testRejectsTruncatedFrame() {
        XCTAssertThrowsError(try BMAPFrame.parse([31, 10, 3, 5, 0]))
    }

    func testModeIndexes() throws {
        XCTAssertEqual(try ListeningMode.aware.index(for: .qcUltra2), 1)
        XCTAssertEqual(try ListeningMode.aware.index(for: .qc45), 2)
        XCTAssertThrowsError(try ListeningMode.cinema.index(for: .qc45))
    }

    func testModePresetReconcilesDependentControls() {
        var settings = HeadphoneSettings()
        settings.noiseEnabled = false
        settings.noiseLevel = 3
        settings.immersive = .still

        settings.applyPreset(.aware)

        XCTAssertEqual(settings.mode, .aware)
        XCTAssertTrue(settings.noiseEnabled)
        XCTAssertEqual(settings.noiseLevel, 0)
        XCTAssertEqual(settings.immersive, .off)
    }

    func testImmersionPresetUsesMotionAndFullNoiseControl() {
        var settings = HeadphoneSettings()
        settings.applyPreset(.immersion)

        XCTAssertEqual(settings.mode, .immersion)
        XCTAssertTrue(settings.noiseEnabled)
        XCTAssertEqual(settings.noiseLevel, 10)
        XCTAssertEqual(settings.immersive, .motion)
    }
}
