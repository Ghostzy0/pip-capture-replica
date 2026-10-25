import Foundation

/// The bundle selects appearance and optional features. Missing metadata preserves Pip Core.
enum AppEdition: String, CaseIterable, Sendable {
    case neutralCore = "neutral-core"
    case neutralPlus = "neutral-plus"
    case pipCore = "pip-core"
    case pipPlus = "pip-plus"

    static var isReplica: Bool { current == .neutralCore && Bundle.main.object(forInfoDictionaryKey: "PipCaptureReplica") as? Bool == true }
    static var displayName: String { isReplica ? "Capture Replica" : current.name }
    static var repositoryURL: String { isReplica ? "https://github.com/Ghostzy0/pip-capture-replica" : "https://github.com/Ghostzy0/pip-capture" }
    static var displayVersion: String { isReplica ? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0-alpha.3") : current.version }
    static let infoKey = "PipCaptureEdition"
    static var current: AppEdition { edition(infoDictionary: Bundle.main.infoDictionary) }

    static func edition(infoDictionary: [String: Any]?) -> AppEdition {
        guard let raw = infoDictionary?[infoKey] as? String, let edition = Self(rawValue: raw) else { return .pipCore }
        return edition
    }

    var name: String {
        switch self {
        case .neutralCore: return "Capture Neutral Core"
        case .neutralPlus: return "Capture Neutral Plus"
        case .pipCore: return "Pip Capture"
        case .pipPlus: return "Pip Capture Plus"
        }
    }

    var bundleID: String {
        switch self {
        case .neutralCore: return "com.pipreps.capture.neutral.core"
        case .neutralPlus: return "com.pipreps.capture.neutral.plus"
        case .pipCore: return "com.pipreps.capture"
        case .pipPlus: return "com.pipreps.capture.plus"
        }
    }

    var storageName: String { Self.isReplica && self == .neutralCore ? "Capture Replica" : name }
    var isPip: Bool { self == .pipCore || self == .pipPlus }
    var hasExtras: Bool { self == .neutralPlus || self == .pipPlus }
    var version: String { hasExtras ? "0.2.0-alpha.4" : "0.1.0-alpha.4" }
}
