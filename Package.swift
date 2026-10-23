// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "PipCapture", platforms: [.macOS(.v14)], products: [.executable(name: "PipCapture", targets: ["PipCapture"])], targets: [
.target(name: "CaptureCore"),
.executableTarget(name: "PipCapture", dependencies: ["CaptureCore"]),
.testTarget(name: "CaptureCoreTests", dependencies: ["CaptureCore"]),
.testTarget(name: "PipCaptureAudioTests", dependencies: ["PipCapture"])
])
