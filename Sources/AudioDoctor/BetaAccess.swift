import Foundation

enum BetaAccess {
    static let buildVersion = "0.4.1-beta.1"
    static let validCodes: Set<String> = [
        "SUNO-BETA-2026",
        "AUDIODR-BETA-2026"
    ]

    static func normalize(_ code: String) -> String {
        code
            .uppercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "-")
    }

    static func isValid(_ code: String) -> Bool {
        validCodes.contains(normalize(code))
    }

    static var expiresAt: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 12
        components.day = 31
        components.hour = 23
        components.minute = 59
        components.second = 59
        return Calendar(identifier: .gregorian).date(from: components) ?? Date.distantFuture
    }

    static func isCurrentlyValid(unlockedAt: Date?) -> Bool {
        guard let unlockedAt else { return false }
        return Date() < expiresAt && unlockedAt <= Date()
    }
}

struct ExportFeedbackReport: Codable {
    let appVersion: String
    let createdAt: Date
    let sourceFilename: String
    let settings: RepairOptions
    let channelTarget: String
    let outputFormat: String
    let bitDepth: Int
    let before: AudioAnalysisReport
    let after: AudioAnalysisReport
}
