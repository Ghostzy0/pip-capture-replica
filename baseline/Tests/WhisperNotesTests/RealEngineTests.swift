import Foundation
import XCTest
@testable import WhisperNotesLib

/// Opt-in real baseline comparison with synthetic audio. No download or microphone access.
final class RealEngineTests: XCTestCase {
    func testConfiguredLocalEnginePreservesSyntheticSource() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let input = env["CAPTURE_TEST_AUDIO"], let executable = env["CAPTURE_TEST_ENGINE"], let weights = env["CAPTURE_TEST_WEIGHTS"] else {
            throw XCTSkip("Set CAPTURE_TEST_AUDIO, CAPTURE_TEST_ENGINE and CAPTURE_TEST_WEIGHTS for the synthetic real-engine comparison.")
        }
        let url = URL(fileURLWithPath: input)
        let before = try Data(contentsOf: url)
        let result = try await WhisperService(whisperPath: executable, modelPath: weights, language: "en").transcribe(audioURL: url)
        XCTAssertFalse(result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertEqual(try Data(contentsOf: url), before)
        print("Baseline real local transcript: \(result)")
    }
}
