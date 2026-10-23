import Foundation
import AppKit
import CaptureCore

// Reproducible file-fed checks use the same packaged engine path as the UI.
let arguments = CommandLine.arguments
if arguments.count == 2 && arguments[1] == "--print-configuration" {
    let edition = AppEdition.current
    let report: [String: Any] = ["edition": edition.rawValue, "name": AppEdition.displayName,
        "bundleID": Bundle.main.bundleIdentifier ?? "", "storageName": edition.storageName,
        "version": AppEdition.displayVersion, "isPip": edition.isPip, "hasExtras": edition.hasExtras,
        "isReplica": AppEdition.isReplica, "repositoryURL": AppEdition.repositoryURL]
    do { let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]); print(String(decoding: data, as: UTF8.self)); exit(0) }
    catch { fputs("Configuration could not be encoded.\n", stderr); exit(1) }
} else if arguments.count == 6 && arguments[1] == "--transcribe-file" {
    let audio = URL(fileURLWithPath: arguments[2]), executable = URL(fileURLWithPath: arguments[3]), weights = URL(fileURLWithPath: arguments[4]), output = URL(fileURLWithPath: arguments[5])
    Task {
        do {
            guard !FileManager.default.fileExists(atPath: output.path),
                  ![audio, executable, weights].map({ $0.resolvingSymlinksInPath().standardizedFileURL }).contains(output.resolvingSymlinksInPath().standardizedFileURL) else {
                fputs("Output must be a new file distinct from every input.\n", stderr); exit(1)
            }
            let worker = LocalTranscriber(configuration: .init(executableURL: executable, modelURL: weights, language: "en"))
            let result = try await worker.transcribe(audioURL: audio)
            let report: [String: Any] = ["text": result.text, "provenance": result.provenance, "segments": result.segments.map { ["start": $0.start, "end": $0.end, "text": $0.text] }]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .withoutOverwriting)
            exit(0)
        } catch { fputs("File transcription failed: \(error.localizedDescription)\n", stderr); exit(1) }
    }
    dispatchMain()
} else {
    PipCaptureApp.main()
}
