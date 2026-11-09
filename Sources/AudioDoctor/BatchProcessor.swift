import AVFoundation
import Foundation

enum BatchMode: String, CaseIterable, Identifiable {
    case analyze = "analyze"
    case repair = "repair"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .analyze: return "只分析 / 标注报告"
        case .repair: return "修复并导出"
        }
    }
}

struct BatchSettings {
    var mode: BatchMode = .analyze
    var repair = RepairOptions()
    var channelTarget = "keep"
    var outputFormat = "wav"
    var bitDepth = 24
    var overwriteExisting = false
}

struct BatchRecord: Identifiable, Codable {
    var id = UUID()
    let sourcePath: String
    let fileName: String
    let status: String
    let grade: String
    let verdict: String
    let durationSeconds: Double
    let sampleRate: Float
    let channels: Int
    let integratedLUFS: Float?
    let truePeakDb: Float
    let clippingPercent: Float
    let crestFactorDb: Float
    let stereoCorrelation: Float?
    let stereoWidthPercent: Float?
    let channelBalanceDb: Float?
    let monoFoldDownLossDb: Float?
    let spatialScore: Float?
    let lowEnergyPercent: Float
    let hissRatioDb: Float?
    let aiFeelScore: Float?
    let artifactScores: ArtifactScores?
    let issueIntervals: [IssueInterval]
    let musicKey: String?
    let musicKeyConfidence: Float?
    let tempoBPM: Float?
    let timeSignature: String?
    let leadPart: String?
    let supportParts: String?
    let arrangementConfidence: Float?

    var artifactHiss: Float? { artifactScores?.hiss }
    var artifactShimmer: Float? { artifactScores?.shimmer }
    var artifactSpectralHole: Float? { artifactScores?.spectralHole }
    var artifactPhaseInstability: Float? { artifactScores?.phaseInstability }
    var artifactTransientSmear: Float? { artifactScores?.transientSmear }
    var artifactStereoAnomaly: Float? { artifactScores?.stereoAnomaly }
    var artifactOverall: Float? { artifactScores?.overall }
    let failedChecks: [String]
    let reviewChecks: [String]
    let outputPath: String?
    let processedLUFS: Float?
    let processedTruePeakDb: Float?
    let error: String?
}

struct BatchProgress {
    var total = 0
    var completed = 0
    var succeeded = 0
    var failed = 0
    var skipped = 0
    var currentFile: String?
    var startedAt: Date?
    var finishedAt: Date?
    var reportURL: URL?

    var fractionCompleted: Double {
        total > 0 ? Double(completed) / Double(total) : 0
    }
}

struct BatchSummary {
    let total: Int
    let succeeded: Int
    let failed: Int
    let skipped: Int
    let cancelled: Bool
    let reportURL: URL?
    let htmlReportURL: URL?
    let aggregate: BatchAggregate?
}

final class BatchCancellation {
    private(set) var isCancelled = false
    private let lock = NSLock()

    func cancel() {
        lock.lock()
        isCancelled = true
        lock.unlock()
    }
}

enum BatchProcessor {
    static let supportedExtensions: Set<String> = ["wav", "aiff", "aif", "m4a", "mp3", "flac", "caf"]

    static func audioFiles(at root: URL) throws -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
            throw NSError(domain: "AudioDoctorBatch", code: 1, userInfo: [NSLocalizedDescriptionKey: "路径不存在"])
        }
        guard isDirectory.boolValue else {
            guard supportedExtensions.contains(root.pathExtension.lowercased()) else { return [] }
            return [root]
        }

        var result: [URL] = []
        var directories: [URL] = [root]
        while let directory = directories.popLast() {
            let children = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
                if values.isDirectory == true {
                    directories.append(child)
                } else if values.isRegularFile == true && supportedExtensions.contains(child.pathExtension.lowercased()) {
                    result.append(child)
                }
            }
        }
        return result.sorted { $0.standardizedFileURL.path < $1.standardizedFileURL.path }
    }

    static func run(
        input: URL,
        output: URL,
        settings: BatchSettings,
        referenceURL: URL?,
        progress: @escaping (BatchProgress) -> Void,
        cancellation: BatchCancellation
    ) throws -> (summary: BatchSummary, records: [BatchRecord]) {
        let files = try audioFiles(at: input)
        guard !files.isEmpty else {
            throw NSError(domain: "AudioDoctorBatch", code: 2, userInfo: [NSLocalizedDescriptionKey: "没有找到可处理的音频文件"])
        }

        let inputIsDirectory = (try? input.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let inputRoot = inputIsDirectory ? input.standardizedFileURL : input.deletingLastPathComponent().standardizedFileURL
        let outputRoot = output.standardizedFileURL
        if inputIsDirectory,
           outputRoot.path == inputRoot.path || outputRoot.path.hasPrefix(inputRoot.path + "/") {
            throw NSError(domain: "AudioDoctorBatch", code: 3, userInfo: [NSLocalizedDescriptionKey: "输出文件夹不能放在输入文件夹内部，避免重复处理"])
        }
        try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)

        var referenceChannels: [[Float]]?
        if let referenceURL, settings.mode == .repair {
            referenceChannels = try AudioIO.loadChannels(url: referenceURL).channels
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let reportURL = outputRoot.appendingPathComponent("AudioDoctor-Batch-Report-\(formatter.string(from: Date())).csv")
        let header = "序号,状态,等级,结论,文件名,源文件,时长秒,采样率,声道,综合响度LUFS,真峰dBTP,削波百分比,峰值因子dB,相位相关性,立体声宽度百分比,左右电平差dB,单声道折叠损失dB,空间展开指数,低频能量百分比,高频噪声dB,疑似AI感,调性,调性置信度,节拍BPM,拍号推测,主奏推测,辅助层,配器置信度,沙声伪影,金属闪烁,频谱空洞,相位不稳定,瞬态模糊,立体声异常,AI伪影总分,问题定位,失败项,复核项,输出文件,处理后LUFS,处理后真峰dBTP,错误\n"
        let csvHeaderData = Data(("\u{FEFF}" + header).utf8)
        try csvHeaderData.write(to: reportURL, options: .atomic)
        let csvHandle = try FileHandle(forWritingTo: reportURL)
        csvHandle.seekToEndOfFile()

        var state = BatchProgress(total: files.count, startedAt: Date())
        var records: [BatchRecord] = []

        for (index, file) in files.enumerated() {
            if cancellation.isCancelled { break }
            state.currentFile = file.lastPathComponent
            progress(state)

            let record = autoreleasepool { () -> BatchRecord in
                processOne(
                    file,
                    index: index,
                    inputRoot: inputRoot,
                    outputRoot: outputRoot,
                    settings: settings,
                    referenceChannels: referenceChannels
                )
            }
            records.append(record)
            csvHandle.write(Data((csvRow(for: record, index: index + 1)).utf8))

            switch record.status {
            case "成功": state.succeeded += 1
            case "跳过": state.skipped += 1
            default: state.failed += 1
            }
            state.completed += 1
            progress(state)
        }

        try? csvHandle.close()
        let aggregate = BatchAggregate.summarize(records: records)
        let htmlURL = try BatchReportWriter.writeHTML(
            records: records,
            aggregate: aggregate,
            csvURL: reportURL,
            outputFolder: outputRoot,
            cancelled: cancellation.isCancelled
        )
        state.currentFile = nil
        state.finishedAt = Date()
        state.reportURL = reportURL
        progress(state)

        return (
            BatchSummary(
                total: files.count,
                succeeded: state.succeeded,
                failed: state.failed,
                skipped: state.skipped,
                cancelled: cancellation.isCancelled,
                reportURL: reportURL,
                htmlReportURL: htmlURL,
                aggregate: aggregate
            ),
            records
        )
    }

    private static func processOne(
        _ file: URL,
        index: Int,
        inputRoot: URL,
        outputRoot: URL,
        settings: BatchSettings,
        referenceChannels: [[Float]]?
    ) -> BatchRecord {
        func failed(_ error: Error) -> BatchRecord {
            makeRecord(
                source: file,
                status: "失败",
                report: nil,
                processedReport: nil,
                outputPath: nil,
                error: error.localizedDescription
            )
        }

        do {
            let relativeParent = file.standardizedFileURL.deletingLastPathComponent().path
                .replacingOccurrences(of: inputRoot.path, with: "")
            let cleanRelativeParent = relativeParent.hasPrefix("/")
                ? String(relativeParent.dropFirst()) : relativeParent
            let suffix = outputSuffix(target: settings.channelTarget, repairing: settings.mode == .repair)
            let destinationDirectory = cleanRelativeParent.isEmpty
                ? outputRoot
                : outputRoot.appendingPathComponent(cleanRelativeParent, isDirectory: true)
            let outputURL = destinationDirectory
                .appendingPathComponent(file.deletingPathExtension().lastPathComponent + suffix)
                .appendingPathExtension(settings.outputFormat)

            if !settings.overwriteExisting && FileManager.default.fileExists(atPath: outputURL.path) {
                return makeRecord(
                    source: file,
                    status: "跳过",
                    report: nil,
                    processedReport: nil,
                    outputPath: outputURL.path,
                    error: "输出已存在"
                )
            }

            let loaded = try AudioIO.loadChannels(url: file)
            let sourceReport = AudioAnalyzer.analyze(
                channels: loaded.channels,
                sampleRate: loaded.sampleRate,
                filename: file.lastPathComponent
            )

            if settings.mode == .analyze {
                return makeRecord(
                    source: file,
                    status: "成功",
                    report: sourceReport,
                    processedReport: nil,
                    outputPath: nil,
                    error: nil
                )
            }

            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            var channels = AudioProcessor.repair(
                channels: loaded.channels,
                sampleRate: loaded.sampleRate,
                options: settings.repair,
                referenceChannels: referenceChannels
            )
            let analysisSource = channels
            if settings.channelTarget != "keep" {
                channels = try AudioProcessor.convert(
                    channels: channels,
                    sampleRate: loaded.sampleRate,
                    target: settings.channelTarget
                )
            }
            do {
                try AudioIO.write(
                    channels: channels,
                    sampleRate: loaded.sampleRate,
                    url: outputURL,
                    bitDepth: settings.bitDepth
                )
            } catch {
                try? FileManager.default.removeItem(at: outputURL)
                throw error
            }
            let processedReport = AudioAnalyzer.analyze(
                channels: analysisSource,
                sampleRate: loaded.sampleRate,
                filename: outputURL.lastPathComponent
            )
            return makeRecord(
                source: file,
                status: "成功",
                report: sourceReport,
                processedReport: processedReport,
                outputPath: outputURL.path,
                error: nil
            )
        } catch {
            return failed(error)
        }
    }

    private static func makeRecord(
        source: URL,
        status: String,
        report: AudioAnalysisReport?,
        processedReport: AudioAnalysisReport?,
        outputPath: String?,
        error: String?
    ) -> BatchRecord {
        let assessment = report.map { LabelStandards.assess($0) }
        let sourceReport = report
        var lowEnergy: Float = 0
        if let sourceReport {
            var total: Float = 0
            for band in sourceReport.bandEnergies where band.lowHz >= 20 && band.highHz <= 350 {
                total += band.energyPercent
            }
            lowEnergy = total
        }
        return BatchRecord(
            sourcePath: source.standardizedFileURL.path,
            fileName: source.lastPathComponent,
            status: status,
            grade: assessment?.grade ?? "—",
            verdict: assessment?.verdict ?? (status == "跳过" ? "输出已存在，未重复处理" : "未生成技术评估"),
            durationSeconds: sourceReport?.durationSeconds ?? 0,
            sampleRate: sourceReport?.sampleRate ?? 0,
            channels: sourceReport?.channels ?? 0,
            integratedLUFS: sourceReport?.integratedLUFS,
            truePeakDb: sourceReport?.truePeakDb ?? -120,
            clippingPercent: sourceReport?.clippingPercent ?? 0,
            crestFactorDb: sourceReport?.crestFactorDb ?? 0,
            stereoCorrelation: sourceReport?.stereoCorrelation,
            stereoWidthPercent: sourceReport?.stereoWidthPercent,
            channelBalanceDb: sourceReport?.channelBalanceDb,
            monoFoldDownLossDb: sourceReport?.monoFoldDownLossDb,
            spatialScore: sourceReport?.spatialScore,
            lowEnergyPercent: lowEnergy,
            hissRatioDb: sourceReport?.hissRatioDb,
            aiFeelScore: sourceReport?.aiFeelScore,
            artifactScores: sourceReport?.artifactScores,
            issueIntervals: sourceReport?.issueIntervals ?? [],
            musicKey: sourceReport?.musicStructure?.tonality?.bestKeyName,
            musicKeyConfidence: sourceReport?.musicStructure?.tonality?.confidence,
            tempoBPM: sourceReport?.musicStructure?.tempo?.bpm,
            timeSignature: sourceReport?.musicStructure?.tempo?.timeSignatureEstimate,
            leadPart: sourceReport?.musicStructure?.arrangement?.leadSummary,
            supportParts: sourceReport?.musicStructure?.arrangement?.supportSummary,
            arrangementConfidence: sourceReport?.musicStructure?.arrangement?.confidence,
            failedChecks: assessment?.failedNames ?? [],
            reviewChecks: assessment?.reviewNames ?? [],
            outputPath: outputPath,
            processedLUFS: processedReport?.integratedLUFS,
            processedTruePeakDb: processedReport?.truePeakDb,
            error: error
        )
    }

    private static func outputSuffix(target: String, repairing: Bool) -> String {
        let targetSuffix: String
        switch target {
        case "mono": targetSuffix = "-mono"
        case "stereo": targetSuffix = "-stereo"
        case "surround51": targetSuffix = "-5.1"
        case "ambix": targetSuffix = "-AmbiX"
        default: targetSuffix = ""
        }
        return (repairing ? "-repaired" : "-converted") + targetSuffix
    }

    private static func csvRow(for record: BatchRecord, index: Int) -> String {
        let fields: [String] = [
            String(index),
            record.status,
            record.grade,
            record.verdict,
            record.fileName,
            record.sourcePath,
            String(format: "%.3f", record.durationSeconds),
            String(Int(record.sampleRate)),
            String(record.channels),
            record.integratedLUFS.map { String(format: "%.2f", $0) } ?? "",
            String(format: "%.2f", record.truePeakDb),
            String(format: "%.5f", record.clippingPercent),
            String(format: "%.2f", record.crestFactorDb),
            record.stereoCorrelation.map { String(format: "%.3f", $0) } ?? "",
            record.stereoWidthPercent.map { String(format: "%.2f", $0) } ?? "",
            record.channelBalanceDb.map { String(format: "%.2f", $0) } ?? "",
            record.monoFoldDownLossDb.map { String(format: "%.2f", $0) } ?? "",
            record.spatialScore.map { String(format: "%.1f", $0) } ?? "",
            String(format: "%.2f", record.lowEnergyPercent),
            record.hissRatioDb.map { String(format: "%.2f", $0) } ?? "",
            record.aiFeelScore.map { String(format: "%.0f", $0) } ?? "",
            record.musicKey ?? "",
            record.musicKeyConfidence.map { String(format: "%.0f%%", $0 * 100) } ?? "",
            record.tempoBPM.map { String(format: "%.1f", $0) } ?? "",
            record.timeSignature ?? "",
            record.leadPart ?? "",
            record.supportParts ?? "",
            record.arrangementConfidence.map { String(format: "%.0f%%", $0 * 100) } ?? "",
            record.artifactHiss.map { String(format: "%.0f", $0) } ?? "",
            record.artifactShimmer.map { String(format: "%.0f", $0) } ?? "",
            record.artifactSpectralHole.map { String(format: "%.0f", $0) } ?? "",
            record.artifactPhaseInstability.map { String(format: "%.0f", $0) } ?? "",
            record.artifactTransientSmear.map { String(format: "%.0f", $0) } ?? "",
            record.artifactStereoAnomaly.map { String(format: "%.0f", $0) } ?? "",
            record.artifactOverall.map { String(format: "%.0f", $0) } ?? "",
            record.issueIntervals.prefix(12).map {
                String(format: "%.1f-%.1fs %@", $0.startTime, $0.endTime, $0.issue)
            }.joined(separator: "；"),
            record.failedChecks.joined(separator: "；"),
            record.reviewChecks.joined(separator: "；"),
            record.outputPath ?? "",
            record.processedLUFS.map { String(format: "%.2f", $0) } ?? "",
            record.processedTruePeakDb.map { String(format: "%.2f", $0) } ?? "",
            record.error ?? ""
        ]
        return fields.map(csvEscape).joined(separator: ",") + "\n"
    }

    private static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}
