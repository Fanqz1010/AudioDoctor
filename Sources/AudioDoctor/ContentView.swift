import AVFoundation
import SwiftUI

final class AppModel: ObservableObject {
    @Published var inputURL: URL?
    @Published var referenceURL: URL?
    @Published var report: AudioAnalysisReport?
    @Published var referenceReport: AudioAnalysisReport?
    @Published var processedReport: AudioAnalysisReport?
    @Published var isWorking = false
    @Published var message: String?
    @Published var errorMessage: String?
    @Published var repair = RepairOptions()
    @Published var channelTarget = "keep"
    @Published var outputFormat = "wav"
    @Published var bitDepth = 24

    // Internal-beta export center. The code is a friendly gate for early users,
    // not DRM or a commercial licensing system.
    @Published var isExportCenterVisible = false
    @Published var betaCodeInput = ""
    @Published var betaUnlockError: String?
    @Published var isBetaUnlocked = false
    private var betaUnlockedAt: Date?

    init() {
#if APP_STORE_BUILD
        // The App Store distribution is sold as a complete app. Internal beta
        // codes remain available only in the GitHub/internal build.
        isBetaUnlocked = true
#else
        let savedUnlockedAt = UserDefaults.standard.object(forKey: "AudioDoctor.betaUnlockedAt") as? Date
        betaUnlockedAt = savedUnlockedAt
        isBetaUnlocked = BetaAccess.isCurrentlyValid(unlockedAt: savedUnlockedAt)
#endif
    }

    // Separate thousand-file batch workspace.
    @Published var selectedWorkspace = "annotation"
    @Published var batchSettings = BatchSettings()
    @Published var batchInputURL: URL?
    @Published var batchOutputURL: URL?
    @Published var batchReferenceURL: URL?
    @Published var batchFileCount = 0
    @Published var isScanningBatch = false
    @Published var isBatchRunning = false
    @Published var batchProgress = BatchProgress()
    @Published var batchRecords: [BatchRecord] = []
    @Published var batchAggregate: BatchAggregate?
    @Published var batchHTMLReportURL: URL?
    @Published var batchMessage: String?
    @Published var batchErrorMessage: String?
    private var batchCancellation: BatchCancellation?

    func loadBatchInput(url: URL) {
        batchErrorMessage = nil
        batchMessage = nil
        isScanningBatch = true
        batchInputURL = url
        batchFileCount = 0
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let files = try BatchProcessor.audioFiles(at: url)
                DispatchQueue.main.async {
                    self.batchFileCount = files.count
                    self.isScanningBatch = false
                    self.batchMessage = files.isEmpty ? "未找到支持的音频文件" : "已找到 \(files.count) 个音频文件"
                }
            } catch {
                DispatchQueue.main.async {
                    self.isScanningBatch = false
                    self.batchErrorMessage = "扫描失败：\(error.localizedDescription)"
                }
            }
        }
    }

    func chooseBatchInput() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "选择一个音频文件夹，或选择单个音频文件"
        if panel.runModal() == .OK, let url = panel.url {
            loadBatchInput(url: url)
        }
    }

    func chooseBatchOutput() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "选择批量报告和导出音频的文件夹"
        if panel.runModal() == .OK, let url = panel.url {
            batchOutputURL = url
        }
    }

    func chooseBatchReference() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            batchReferenceURL = url
            batchMessage = "批量参考曲已选择：\(url.lastPathComponent)"
        }
    }

    func startBatch() {
        guard let input = batchInputURL, let output = batchOutputURL else {
            batchErrorMessage = "请先选择批量输入和输出文件夹"
            return
        }
        guard !isBatchRunning else { return }
        let settings = batchSettings
        if settings.mode == .repair && !isBetaUnlocked {
            isExportCenterVisible = true
            batchErrorMessage = "批量修复导出属于内测功能，请先输入内测码。"
            return
        }
        let reference = batchReferenceURL
        let cancellation = BatchCancellation()
        batchCancellation = cancellation
        isBatchRunning = true
        batchErrorMessage = nil
        batchMessage = nil
        batchRecords = []
        batchProgress = BatchProgress(total: batchFileCount, startedAt: Date())

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try BatchProcessor.run(
                    input: input,
                    output: output,
                    settings: settings,
                    referenceURL: reference,
                    progress: { progress in
                        DispatchQueue.main.async {
                            self.batchProgress = progress
                        }
                    },
                    cancellation: cancellation
                )
                DispatchQueue.main.async {
                    self.batchRecords = result.records
                    self.batchAggregate = result.summary.aggregate
                    self.batchHTMLReportURL = result.summary.htmlReportURL
                    var finalProgress = self.batchProgress
                    finalProgress.reportURL = result.summary.reportURL
                    finalProgress.finishedAt = Date()
                    self.batchProgress = finalProgress
                    self.isBatchRunning = false
                    self.batchMessage = result.summary.cancelled
                        ? "批量处理已取消：成功 \(result.summary.succeeded)，失败 \(result.summary.failed)，跳过 \(result.summary.skipped)"
                        : "批量处理完成：成功 \(result.summary.succeeded)，失败 \(result.summary.failed)，跳过 \(result.summary.skipped)"
                }
            } catch {
                DispatchQueue.main.async {
                    self.isBatchRunning = false
                    self.batchErrorMessage = "批量处理失败：\(error.localizedDescription)"
                }
            }
        }
    }

    func cancelBatch() {
        batchCancellation?.cancel()
        batchMessage = "正在取消，当前文件完成后会停止"
    }

    func loadFile(url: URL) {
        errorMessage = nil
        message = nil
        isWorking = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let started = Date()
                let loaded = try AudioIO.loadChannels(url: url)
                let analysis = AudioAnalyzer.analyze(channels: loaded.channels, sampleRate: loaded.sampleRate, filename: url.lastPathComponent)
                DispatchQueue.main.async {
                    self.inputURL = url
                    self.report = analysis
                    self.processedReport = nil
                    self.isWorking = false
                    self.message = String(format: "分析完成，用时 %.1f 秒", Date().timeIntervalSince(started))
                }
            } catch {
                DispatchQueue.main.async {
                    self.isWorking = false
                    self.errorMessage = "无法读取音频：\(error.localizedDescription)"
                }
            }
        }
    }

    func loadReference(url: URL) {
        referenceURL = url
        referenceReport = nil
        message = "参考曲已导入：\(url.lastPathComponent)"
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let loaded = try AudioIO.loadChannels(url: url)
                let analysis = AudioAnalyzer.analyze(channels: loaded.channels, sampleRate: loaded.sampleRate, filename: url.lastPathComponent)
                DispatchQueue.main.async {
                    self.referenceReport = analysis
                    self.message = "参考曲分析完成：\(url.lastPathComponent)"
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "参考曲无法读取：\(error.localizedDescription)"
                }
            }
        }
    }

    func openExportCenter() {
        betaUnlockError = nil
        isExportCenterVisible = true
    }

    func unlockBetaAccess() {
        if BetaAccess.isValid(betaCodeInput) {
            let now = Date()
            betaUnlockedAt = now
            isBetaUnlocked = true
            betaUnlockError = nil
            UserDefaults.standard.set(now, forKey: "AudioDoctor.betaUnlockedAt")
            message = "内测导出权限已开启，有效期至 2026-12-31。"
        } else {
            betaUnlockError = "内测码不正确。请检查大小写、空格或联系开发者。"
        }
    }

    func applySunoRecommendedSettings(vocalFocus: Bool) {
        repair.presetRawValue = (vocalFocus ? ContentPreset.sunoVocal : .sunoPop).rawValue
        repair.deHiss = true
        repair.fullness = true
        repair.lowFrequencyMono = true
        repair.transientRecovery = true
        repair.exciter = false
        repair.loudnessNormalize = true
        repair.targetLUFS = -14
        repair.strength = 0.8
        channelTarget = "keep"
        outputFormat = "wav"
        bitDepth = 24
        message = vocalFocus ? "已应用 Suno 人声内测推荐参数。" : "已应用 Suno 流行内测推荐参数。"
    }

    func processAndExport() {
        guard inputURL != nil else { return }
        guard isBetaUnlocked else {
            openExportCenter()
            errorMessage = "导出模块正在内测，请先输入内测码。"
            return
        }
        isExportCenterVisible = false
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.audio]
        panel.nameFieldStringValue = processedName()
        panel.begin { response in
            guard response == .OK, let outputURL = panel.url else { return }
            self.runProcessing(outputURL: outputURL)
        }
    }

    private func processedName() -> String {
        guard let inputURL else { return "processed.wav" }
        let base = inputURL.deletingPathExtension().lastPathComponent
        let suffix: String
        switch channelTarget {
        case "mono": suffix = "repaired-mono"
        case "stereo": suffix = "repaired-stereo"
        case "surround51": suffix = "repaired-5.1"
        case "ambix": suffix = "repaired-AmbiX"
        default: suffix = "repaired"
        }
        return "\(base)-\(suffix).\(outputFormat)"
    }

    private func runProcessing(outputURL: URL) {
        isWorking = true
        errorMessage = nil
        message = nil
        guard let input = inputURL else { return }
        let options = repair
        let target = channelTarget
        let bits = bitDepth
        let reference = referenceURL
        let beforeReport = report
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let loaded = try AudioIO.loadChannels(url: input)
                let referenceChannels = reference == nil ? nil : try AudioIO.loadChannels(url: reference!).channels
                // Repair the source first, then convert. The repair and loudness chain
                // is designed around normal speaker channels, not AmbiX components.
                var channels = AudioProcessor.repair(channels: loaded.channels, sampleRate: loaded.sampleRate, options: options, referenceChannels: referenceChannels)
                let analysisSource = channels
                if target != "keep" {
                    channels = try AudioProcessor.convert(channels: channels, sampleRate: loaded.sampleRate, target: target)
                }
                try AudioIO.write(channels: channels, sampleRate: loaded.sampleRate, url: outputURL, bitDepth: bits)
                // Keep metrics on the repaired source because W/Y/Z/X are not speaker
                // signals and would make stereo phase/loudness cards misleading.
                let after = AudioAnalyzer.analyze(channels: analysisSource, sampleRate: loaded.sampleRate, filename: outputURL.lastPathComponent)
                let feedback = ExportFeedbackReport(
                    appVersion: BetaAccess.buildVersion,
                    createdAt: Date(),
                    sourceFilename: input.lastPathComponent,
                    settings: options,
                    channelTarget: target,
                    outputFormat: self.outputFormat,
                    bitDepth: bits,
                    before: beforeReport ?? after,
                    after: after
                )
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                let feedbackURL = URL(fileURLWithPath: outputURL.path + ".report.json")
                try encoder.encode(feedback).write(to: feedbackURL, options: .atomic)
                DispatchQueue.main.async {
                    self.isWorking = false
                    self.processedReport = after
                    self.message = "处理完成：\(outputURL.lastPathComponent)。反馈报告已生成：\(feedbackURL.lastPathComponent)"
                }
            } catch {
                DispatchQueue.main.async {
                    self.isWorking = false
                    self.errorMessage = "处理失败：\(error.localizedDescription)"
                }
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.isWorking { ProgressView("正在分析音频…").padding() }
            switch model.selectedWorkspace {
            case "annotation":
                AnnotationWorkbenchView()
            case "batch":
                BatchWorkspaceView()
                    .padding(20)
            case "content":
                ContentOptimizationWorkspaceView()
                    .padding(20)
            case "repair":
                RepairStudioView()
            default:
                AnnotationWorkbenchView()
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $model.isExportCenterVisible) {
            ExportCenterView()
                .environmentObject(model)
                .frame(width: 620)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Audio Doctor 音频体检与修复")
                    .font(.title2.weight(.semibold))
                Text(headerVersionDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("工作台", selection: $model.selectedWorkspace) {
                Text("标注工作台").tag("annotation")
                Text("修复工作台").tag("repair")
                Text("批量标注").tag("batch")
                Text("内容优化").tag("content")
            }
            .pickerStyle(.segmented)
            .frame(width: 430)
            #if APP_STORE_BUILD
            Label("完整版已解锁", systemImage: "checkmark.seal")
                .font(.caption)
                .foregroundStyle(.green)
            #else
            if model.isBetaUnlocked {
                Label("内测已开启", systemImage: "checkmark.seal")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Button {
                    model.openExportCenter()
                } label: {
                    Label("导出内测", systemImage: "key")
                }
                .controlSize(.small)
            }
            #endif
            if model.isWorking { ProgressView().controlSize(.small) }
        }
        .padding(20)
    }

    private var headerVersionDescription: String {
        #if APP_STORE_BUILD
        return "v0.5.0 · 五大类标注 / 音乐结构 / 转调节拍 / 和弦功能 / 修复工作台"
        #else
        return "v0.5.0 内测版 · 五大类标注 / 音乐结构 / 转调节拍 / 和弦功能 / 修复工作台"
        #endif
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 16) {
            DropZone(title: "拖入要检查的音频", subtitle: "支持 WAV / AIFF / M4A / MP3") { url in
                model.loadFile(url: url)
            }
            DropZone(title: "可选：拖入参考曲", subtitle: "用于判断「丰满度」差距") { url in
                model.loadReference(url: url)
            }
            GroupBox("一键转换") {
                Picker("声道", selection: $model.channelTarget) {
                    Text("保持原样").tag("keep")
                    Text("立体声 → 单声道").tag("mono")
                    Text("单声道 → 立体声").tag("stereo")
                    Text("立体声 → 5.1 环绕声").tag("surround51")
                    Text("立体声 → AmbiX 全景声").tag("ambix")
                }
                .pickerStyle(.radioGroup)
                if model.channelTarget == "surround51" {
                    Text("输出 6 声道：L、R、C、LFE、Ls、Rs")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if model.channelTarget == "ambix" {
                    Text("输出一阶 AmbiX：W、Y、Z、X（ACN/SN3D）")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("这是开源空间音频格式，不是 Dolby Atmos 母版")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            GroupBox("AI 伪影修复策略") {
                Group {
                Picker("内容预设", selection: $model.repair.presetRawValue) {
                    ForEach(ContentPreset.allCases) { preset in
                        Text(preset.title).tag(preset.rawValue)
                    }
                }
                Text(model.repair.preset.summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Toggle("去高频沙沙声 / 稳态伪影", isOn: $model.repair.deHiss)
                Toggle("补足低频与身体感", isOn: $model.repair.fullness)
                Toggle("使用参考曲频响匹配", isOn: $model.repair.matchReference)
                    .disabled(model.referenceURL == nil)
                }
                Group {
                Toggle("低频单声道化，改善相位兼容", isOn: $model.repair.lowFrequencyMono)
                Toggle("瞬态恢复，减少鼓点/辅音发糊", isOn: $model.repair.transientRecovery)
                Toggle("增加细节与空气感", isOn: $model.repair.exciter)
                Toggle("响度标准化", isOn: $model.repair.loudnessNormalize)
                HStack {
                    Text("目标响度")
                    TextField("-14", value: $model.repair.targetLUFS, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                    Text("LUFS")
                }
                HStack {
                    Text("修复强度")
                    Slider(value: $model.repair.strength, in: 0...1.5, step: 0.1)
                    Text(String(format: "%.1f", model.repair.strength))
                        .monospacedDigit()
                        .frame(width: 30)
                }
                }
            }
            GroupBox("导出") {
                Picker("格式", selection: $model.outputFormat) {
                    Text("WAV").tag("wav")
                    Text("AIFF").tag("aiff")
                }
                Picker("位深", selection: $model.bitDepth) {
                    Text("16-bit").tag(16)
                    Text("24-bit").tag(24)
                }
                Button {
                    model.processAndExport()
                } label: {
                    Label("处理并导出", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command)
            }
            if let message = model.message {
                Label(message, systemImage: "checkmark.circle").foregroundStyle(.green)
            }
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            }
            Spacer()
        }
        .frame(width: 340)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("把音频拖到左侧，就会显示客观指标")
                .font(.headline)
            Text("包括响度、真峰、削波、相位、立体声宽度、频段分布和疑似 AI 感评分")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func analysis(_ report: AudioAnalysisReport) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                MetricCard(title: "综合响度", value: report.integratedLUFS.map { String(format: "%.1f LUFS", $0) } ?? "—", quality: loudnessQuality(report.integratedLUFS))
                MetricCard(title: "真峰", value: String(format: "%.2f dBTP", report.truePeakDb), quality: report.truePeakDb <= -1 ? .good : .warning)
                MetricCard(title: "失真风险", value: report.distortionRisk, quality: report.distortionRisk.hasPrefix("低") ? .good : .warning)
                MetricCard(title: "相位相关性", value: report.stereoCorrelation.map { String(format: "%.2f", $0) } ?? "单声道", quality: phaseQuality(report.stereoCorrelation))
                MetricCard(title: "立体声宽度", value: report.stereoWidthPercent.map { String(format: "%.0f%%", $0) } ?? "—", quality: .neutral)
                MetricCard(title: "疑似 AI 感", value: String(format: "%.0f / 100", report.aiFeelScore ?? 0), quality: aiQuality(report.aiFeelScore))
            }
            GroupBox("基础信息") {
                Grid(alignment: .leading, horizontalSpacing: 30, verticalSpacing: 8) {
                    GridRow { Text("文件"); Text(report.filename) }
                    GridRow { Text("时长"); Text(String(format: "%.1f 秒", report.durationSeconds)) }
                    GridRow { Text("采样率"); Text(String(format: "%.0f Hz", report.sampleRate)) }
                    GridRow { Text("声道"); Text("\(report.channels)") }
                    GridRow { Text("样本峰值"); Text(String(format: "%.2f dBFS", report.samplePeakDb)) }
                    GridRow { Text("RMS"); Text(String(format: "%.2f dBFS", report.rmsDb)) }
                    GridRow { Text("峰值因子"); Text(String(format: "%.1f dB", report.crestFactorDb)) }
                    GridRow { Text("直流偏移"); Text(String(format: "%.5f", report.dcOffset)) }
                    GridRow { Text("疑似削波采样"); Text("\(report.clippedSamples)") }
                }
            }
            GroupBox("频段能量分布") {
                VStack(spacing: 8) {
                    ForEach(report.bandEnergies) { band in
                        HStack {
                            Text(band.name).frame(width: 60, alignment: .leading)
                            ProgressView(value: min(100, band.energyPercent), total: 100)
                            Text(String(format: "%.1f%%", band.energyPercent)).monospacedDigit().frame(width: 60, alignment: .trailing)
                        }
                    }
                }
            }
            if let reference = model.referenceReport, let current = model.report {
                GroupBox("参考曲对比（能量占比）") {
                    VStack(spacing: 8) {
                        HStack {
                            Text("频段").frame(width: 60, alignment: .leading)
                            Text("当前").frame(width: 70, alignment: .trailing)
                            Text("参考").frame(width: 70, alignment: .trailing)
                            Text("差距").frame(width: 70, alignment: .trailing)
                        }
                        .font(.caption)
                        ForEach(current.bandEnergies) { band in
                            if let ref = reference.bandEnergies.first(where: { $0.name == band.name }) {
                                let difference = ref.energyPercent - band.energyPercent
                                HStack {
                                    Text(band.name).frame(width: 60, alignment: .leading)
                                    Text(String(format: "%.1f%%", band.energyPercent)).monospacedDigit().frame(width: 70, alignment: .trailing)
                                    Text(String(format: "%.1f%%", ref.energyPercent)).monospacedDigit().frame(width: 70, alignment: .trailing)
                                    Text(String(format: "%+.1f%%", difference))
                                        .monospacedDigit()
                                        .foregroundStyle(abs(difference) > 5 ? Color.orange : Color.secondary)
                                        .frame(width: 70, alignment: .trailing)
                                }
                            }
                        }
                    }
                }
            }
            GroupBox("建议") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(report.recommendations, id: \.self) { recommendation in
                        Label(recommendation, systemImage: "checkmark.seal")
                    }
                }
            }
            if let processed = model.processedReport {
                GroupBox("处理前后对比") {
                    VStack(spacing: 8) {
                        comparisonRow("综合响度", before: report.integratedLUFS.map { String(format: "%.1f LUFS", $0) } ?? "—", after: processed.integratedLUFS.map { String(format: "%.1f LUFS", $0) } ?? "—")
                        comparisonRow("真峰", before: String(format: "%.2f dBTP", report.truePeakDb), after: String(format: "%.2f dBTP", processed.truePeakDb))
                        comparisonRow("高频噪声占比", before: String(format: "%.1f dB", report.hissRatioDb ?? -120), after: String(format: "%.1f dB", processed.hissRatioDb ?? -120))
                        comparisonRow("疑似 AI 感", before: String(format: "%.0f / 100", report.aiFeelScore ?? 0), after: String(format: "%.0f / 100", processed.aiFeelScore ?? 0))
                    }
                }
            }
            Text("说明：响度、峰值、相位和频段分布是客观测量；「疑似 AI 感」是基于频段缺失与高频噪声占比的启发式评分，仅作参考，不等于听感最终判决。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func loudnessQuality(_ value: Float?) -> MetricQuality {
        guard let value else { return .neutral }
        if value < -25 || value > -8 { return .warning }
        return .good
    }

    private func phaseQuality(_ value: Float?) -> MetricQuality {
        guard let value else { return .neutral }
        if value < 0.2 { return .warning }
        return .good
    }

    private func aiQuality(_ value: Float?) -> MetricQuality {
        guard let value else { return .neutral }
        if value > 65 { return .warning }
        return .neutral
    }

    private func artifactDashboard(_ report: AudioAnalysisReport) -> some View {
        GroupBox("AI 伪影七维拆解") {
            VStack(alignment: .leading, spacing: 12) {
                if let scores = report.artifactScores {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("AI 伪影总分").font(.caption).foregroundStyle(.secondary)
                            Text(String(format: "%.0f / 100", scores.overall)).font(.title2.weight(.semibold))
                        }
                        Spacer()
                        Text("仅表示可听质量风险，不判断来源，也不能用于规避检测")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ArtifactScoreCard(title: "沙声", score: scores.hiss, detail: "9kHz 以上占比")
                        ArtifactScoreCard(title: "金属闪烁", score: scores.shimmer, detail: "高频能量/平坦度")
                        ArtifactScoreCard(title: "频谱空洞", score: scores.spectralHole, detail: "局部缺频")
                        ArtifactScoreCard(title: "偏薄", score: scores.thinness, detail: "20–350Hz")
                        ArtifactScoreCard(title: "相位不稳", score: scores.phaseInstability, detail: "分窗相关")
                        ArtifactScoreCard(title: "瞬态模糊", score: scores.transientSmear, detail: "包络攻击")
                        ArtifactScoreCard(title: "立体声异常", score: scores.stereoAnomaly, detail: "平衡/折叠/相关")
                    }
                }
            }
        }
    }

    private func issueTimeline(_ report: AudioAnalysisReport) -> some View {
        GroupBox("时间轴 Badcase 定位") {
            VStack(alignment: .leading, spacing: 10) {
                if report.issueIntervals.isEmpty {
                    Text("未发现需要优先复核的时间窗口。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("标注员可先试听以下区间；严重度只代表客观风险，不等于最终听感结论。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(report.issueIntervals.prefix(30)) { interval in
                        HStack(alignment: .top, spacing: 10) {
                            Text(timeRange(interval))
                                .font(.caption.monospacedDigit())
                                .frame(width: 108, alignment: .leading)
                            Text(interval.severity)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(severityColor(interval.severity))
                                .frame(width: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(interval.issue).font(.caption.weight(.semibold))
                                Text("\(interval.evidence) · 建议：\(interval.suggestedFix)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Text(String(format: "%.0f%%", interval.confidence * 100))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    }
                    if report.issueIntervals.count > 30 {
                        Text("其余 \(report.issueIntervals.count - 30) 个区间见完整分析 JSON / 批量 HTML 报告。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func timeRange(_ interval: IssueInterval) -> String {
        String(format: "%.1f – %.1f 秒", interval.startTime, interval.endTime)
    }

    private func severityColor(_ severity: String) -> Color {
        switch severity {
        case "高": return .red
        case "中": return .orange
        default: return .secondary
        }
    }

    private func comparisonRow(_ name: String, before: String, after: String) -> some View {
        HStack {
            Text(name).frame(width: 110, alignment: .leading)
            Text(before).monospacedDigit().frame(width: 100, alignment: .trailing)
            Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
            Text(after).monospacedDigit().frame(width: 100, alignment: .leading)
        }
    }
}

enum MetricQuality { case good, warning, neutral }

struct MetricCard: View {
    var title: String
    var value: String
    var quality: MetricQuality

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold))
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .topTrailing) { circle }
    }

    private var color: Color {
        switch quality {
        case .good: return .green
        case .warning: return .orange
        case .neutral: return .accentColor
        }
    }

    private var circle: some View {
        Circle().fill(color).frame(width: 8, height: 8).padding(10)
    }
}

struct ArtifactScoreCard: View {
    let title: String
    let score: Float
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.caption.weight(.semibold))
                Spacer()
                Text(String(format: "%.0f", score)).font(.caption.monospacedDigit()).foregroundStyle(color)
            }
            ProgressView(value: Double(score) / 100).tint(color)
            Text(detail).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(9)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
    }

    private var color: Color {
        score <= 45 ? .green : (score <= 70 ? .orange : .red)
    }
}

struct DropZone: View {
    var title: String
    var subtitle: String
    var action: (URL) -> Void
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down.doc").font(.title2)
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 110)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isTargeted ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(isTargeted ? Color.accentColor : Color(nsColor: .separatorColor), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                )
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { DispatchQueue.main.async { action(url) } }
            }
            return true
        }
    }
}
