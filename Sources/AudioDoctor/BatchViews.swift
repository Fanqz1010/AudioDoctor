import SwiftUI

struct BatchWorkspaceView: View {
    @EnvironmentObject private var model: AppModel
    @State private var recordFilter = "all"

    private var filteredRecords: [BatchRecord] {
        switch recordFilter {
        case "failed": return model.batchRecords.filter { $0.status == "失败" || $0.grade == "D" }
        case "review": return model.batchRecords.filter { $0.grade == "C" || !$0.reviewChecks.isEmpty }
        case "passed": return model.batchRecords.filter { $0.status != "失败" && $0.grade != "D" }
        default: return model.batchRecords
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            batchControls
                .frame(width: 390)
            batchDashboard
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var batchControls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("批量输入") {
                    DropZone(
                        title: "拖入批量音频文件夹",
                        subtitle: "递归扫描 WAV / AIFF / M4A / MP3 / FLAC"
                    ) { url in
                        model.loadBatchInput(url: url)
                    }
                    HStack(spacing: 8) {
                        Button {
                            model.chooseBatchInput()
                        } label: {
                            Label("选择输入", systemImage: "folder")
                                .frame(maxWidth: .infinity)
                        }
                        Button {
                            model.chooseBatchOutput()
                        } label: {
                            Label("选择输出", systemImage: "arrow.down.folder")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    if model.isScanningBatch {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("正在递归扫描音频…").foregroundStyle(.secondary)
                        }
                    } else if let input = model.batchInputURL {
                        pathRow("输入", input)
                    }
                    if let output = model.batchOutputURL {
                        pathRow("输出", output)
                    }
                    Text("已找到 \(model.batchFileCount) 个音频")
                        .font(.headline)
                }

                GroupBox("批量模式") {
                    Picker("模式", selection: $model.batchSettings.mode) {
                        ForEach(BatchMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.radioGroup)

                    if model.batchSettings.mode == .repair {
                        Group {
                        Divider()
                        Picker("内容预设", selection: $model.batchSettings.repair.presetRawValue) {
                            ForEach(ContentPreset.allCases) { preset in
                                Text(preset.title).tag(preset.rawValue)
                            }
                        }
                        Text(model.batchSettings.repair.preset.summary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Toggle("去高频沙沙声 / 稳态伪影", isOn: $model.batchSettings.repair.deHiss)
                        Toggle("补足低频与身体感", isOn: $model.batchSettings.repair.fullness)
                        Toggle("使用参考曲频响匹配", isOn: $model.batchSettings.repair.matchReference)
                            .disabled(model.batchReferenceURL == nil)
                        }
                        Group {
                        Toggle("低频单声道化", isOn: $model.batchSettings.repair.lowFrequencyMono)
                        Toggle("瞬态恢复", isOn: $model.batchSettings.repair.transientRecovery)
                        Toggle("增加细节与空气感", isOn: $model.batchSettings.repair.exciter)
                        Toggle("响度标准化", isOn: $model.batchSettings.repair.loudnessNormalize)
                        HStack {
                            Text("目标响度")
                            TextField("-14", value: $model.batchSettings.repair.targetLUFS, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 65)
                            Text("LUFS")
                        }
                        HStack {
                            Text("修复强度")
                            Slider(value: $model.batchSettings.repair.strength, in: 0...1.5, step: 0.1)
                            Text(String(format: "%.1f", model.batchSettings.repair.strength))
                                .monospacedDigit()
                                .frame(width: 30)
                        }
                        Button {
                            model.chooseBatchReference()
                        } label: {
                            Label(
                                model.batchReferenceURL == nil ? "选择参考曲（可选）" : "已选参考曲：\(model.batchReferenceURL!.lastPathComponent)",
                                systemImage: "music.note.list"
                            )
                            .lineLimit(1)
                        }
                        }
                    } else {
                        Text("只生成客观标注报告，不修改、不导出音频；适合千级文件快速体检。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if model.batchSettings.mode == .repair {
                    GroupBox("批量输出") {
                        Picker("声道", selection: $model.batchSettings.channelTarget) {
                            Text("保持原样").tag("keep")
                            Text("立体声 → 单声道").tag("mono")
                            Text("单声道 → 立体声").tag("stereo")
                            Text("立体声 → 5.1").tag("surround51")
                            Text("立体声 → AmbiX").tag("ambix")
                        }
                        Picker("格式", selection: $model.batchSettings.outputFormat) {
                            Text("WAV").tag("wav")
                            Text("AIFF").tag("aiff")
                        }
                        Picker("位深", selection: $model.batchSettings.bitDepth) {
                            Text("16-bit").tag(16)
                            Text("24-bit").tag(24)
                        }
                        Toggle("覆盖已存在输出", isOn: $model.batchSettings.overwriteExisting)
                        Text("默认跳过已存在输出，中断后可重新运行作为续跑。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    GroupBox("报告输出") {
                        Text("只生成客观标注 CSV，不修改音频，不生成导出文件。输出文件夹用于存放报告。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if model.isBatchRunning {
                    Button {
                        model.cancelBatch()
                    } label: {
                        Label("取消批量任务", systemImage: "stop.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                } else {
                    Button {
                        model.startBatch()
                    } label: {
                        Label("开始批量处理", systemImage: "play.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(model.batchInputURL == nil || model.batchOutputURL == nil || model.batchFileCount == 0)
                }

                if let message = model.batchMessage {
                    Label(message, systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                }
                if let error = model.batchErrorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var batchDashboard: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("批量进度") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(model.batchProgress.currentFile ?? (model.isBatchRunning ? "准备中" : "等待开始"))
                            .font(.headline)
                            .lineLimit(1)
                        Spacer()
                        Text("\(model.batchProgress.completed) / \(model.batchProgress.total)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: model.batchProgress.fractionCompleted)
                    HStack(spacing: 14) {
                        Text("成功 \(model.batchProgress.succeeded)")
                        Text("失败 \(model.batchProgress.failed)")
                        Text("跳过 \(model.batchProgress.skipped)")
                        if let started = model.batchProgress.startedAt {
                            Text("已运行 \(Int(Date().timeIntervalSince(started))) 秒")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if let report = model.batchProgress.reportURL {
                        pathRow("CSV 报告", report)
                    }
                    if let report = model.batchHTMLReportURL {
                        pathRow("HTML 总结报告", report)
                    }
                }
            }

            if let aggregate = model.batchAggregate {
                BatchAggregateSummaryView(aggregate: aggregate)
            }

            if !model.batchRecords.isEmpty {
                BatchMusicStructureSummaryView(records: model.batchRecords)
            }

            HStack(alignment: .top, spacing: 12) {
                BatchSummaryCard(title: "总数", value: "\(model.batchProgress.total)", color: .accentColor)
                BatchSummaryCard(title: "成功", value: "\(model.batchProgress.succeeded)", color: .green)
                BatchSummaryCard(title: "失败", value: "\(model.batchProgress.failed)", color: .red)
                BatchSummaryCard(title: "跳过", value: "\(model.batchProgress.skipped)", color: .orange)
            }

            GroupBox("标注结果队列") {
                Picker("筛选", selection: $recordFilter) {
                    Text("全部").tag("all")
                    Text("技术异常").tag("failed")
                    Text("需复核").tag("review")
                    Text("可标注").tag("passed")
                }
                .pickerStyle(.segmented)

                if model.batchRecords.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "list.clipboard")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("批量结果会在这里显示")
                        Text("CSV 会同步写入报告文件，即使中途取消也能保留已完成记录")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    List(filteredRecords) { record in
                        BatchRecordRow(record: record)
                    }
                    .listStyle(.inset)
                    .frame(minHeight: 300, maxHeight: .infinity)
                }
            }

            GroupBox("给标注员的客观标准") {
                AnnotationStandardsSummary()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func pathRow(_ title: String, _ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(url.path)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BatchAggregateSummaryView: View {
    let aggregate: BatchAggregate

    var body: some View {
        GroupBox("批量总结与 Badcase 定位") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(["A", "B", "C", "D"], id: \.self) { grade in
                        BatchSummaryCard(
                            title: "\(grade) 级",
                            value: "\(aggregate.gradeCounts[grade, default: 0])",
                            color: gradeColor(grade)
                        )
                    }
                }

                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("集中问题").font(.headline)
                        if aggregate.issueCounts.isEmpty {
                            Text("未发现集中异常").font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(aggregate.issueCounts.prefix(6)) { issue in
                            HStack {
                                Text(issue.name).font(.caption).lineLimit(1)
                                Spacer()
                                Text("\(issue.count)").font(.caption.monospacedDigit())
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("优先复核文件").font(.headline)
                        if aggregate.worstFiles.isEmpty {
                            Text("无高风险文件").font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(aggregate.worstFiles.prefix(8)) { file in
                            HStack {
                                Text(file.fileName).font(.caption).lineLimit(1)
                                Spacer()
                                Text(file.grade).font(.caption.weight(.semibold))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("批次处理建议").font(.headline)
                    ForEach(aggregate.recommendations, id: \.self) { recommendation in
                        Label(recommendation, systemImage: "checkmark.seal")
                            .font(.caption)
                    }
                }
            }
        }
    }

    private func gradeColor(_ grade: String) -> Color {
        switch grade {
        case "A": return .green
        case "B": return .accentColor
        case "C": return .orange
        default: return .red
        }
    }
}

struct BatchMusicStructureSummaryView: View {
    let records: [BatchRecord]

    private var analyzed: [BatchRecord] {
        records.filter { $0.status != "失败" }
    }

    private var keyCounts: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for record in analyzed {
            if let key = record.musicKey { counts[key, default: 0] += 1 }
        }
        return counts.map { (name: $0.key, count: $0.value) }
            .sorted {
                $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count
            }
    }

    private var bpmValues: [Float] {
        analyzed.compactMap(\.tempoBPM).sorted()
    }

    private var medianBPM: Float? {
        guard !bpmValues.isEmpty else { return nil }
        let middle = bpmValues.count / 2
        if bpmValues.count % 2 == 1 { return bpmValues[middle] }
        return (bpmValues[middle - 1] + bpmValues[middle]) / 2
    }

    private var leadCounts: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for record in analyzed {
            if let lead = record.leadPart { counts[lead, default: 0] += 1 }
        }
        return counts.map { (name: $0.key, count: $0.value) }
            .sorted {
                $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count
            }
    }

    var body: some View {
        GroupBox("音乐结构批量总结：调性 / BPM / 主奏") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    BatchSummaryCard(title: "已判断调性", value: "\(keyCounts.reduce(0) { $0 + $1.count })/\(analyzed.count)", color: .accentColor)
                    BatchSummaryCard(title: "BPM 中位数", value: medianBPM.map { String(format: "%.1f", $0) } ?? "—", color: .green)
                    BatchSummaryCard(title: "最常见调性", value: keyCounts.first?.name ?? "—", color: .orange)
                    BatchSummaryCard(title: "最常见主奏", value: leadCounts.first?.name ?? "—", color: .purple)
                }

                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("调性分布").font(.headline)
                        if keyCounts.isEmpty {
                            Text("未形成稳定调性判断").font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(keyCounts.prefix(6), id: \.name) { item in
                            HStack {
                                Text(item.name).font(.caption).lineLimit(1)
                                Spacer()
                                Text("\(item.count)").font(.caption.monospacedDigit())
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("主奏推测分布").font(.headline)
                        if leadCounts.isEmpty {
                            Text("未形成稳定配器判断").font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(leadCounts.prefix(6), id: \.name) { item in
                            HStack {
                                Text(item.name).font(.caption).lineLimit(1)
                                Spacer()
                                Text("\(item.count)").font(.caption.monospacedDigit())
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let low = bpmValues.first, let high = bpmValues.last {
                    Text("BPM 范围：\(String(format: "%.1f", low))–\(String(format: "%.1f", high))。调性、节拍和配器均为启发式推断，建议作为标注参考，不替代人工确认。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct BatchRecordRow: View {
    let record: BatchRecord
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            BatchRecordDetail(record: record)
                .padding(.vertical, 6)
        } label: {
            HStack(spacing: 10) {
                Text(record.grade)
                    .font(.headline.monospaced())
                    .frame(width: 28, height: 28)
                    .background(gradeColor.opacity(0.18), in: Circle())
                    .foregroundStyle(gradeColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.fileName).lineLimit(1)
                    Text(record.verdict)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if !record.failedChecks.isEmpty {
                    Text("异常 \(record.failedChecks.count)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if !record.reviewChecks.isEmpty {
                    Text("复核 \(record.reviewChecks.count)")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text(record.status)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }
        }
    }

    private var gradeColor: Color {
        switch record.grade {
        case "A": return .green
        case "B": return .accentColor
        case "C": return .orange
        default: return .red
        }
    }

    private var statusColor: Color {
        switch record.status {
        case "成功": return .green
        case "跳过": return .orange
        default: return .red
        }
    }
}

struct BatchRecordDetail: View {
    let record: BatchRecord

    private var metrics: [BatchMetricDisplay] {
        var values: [BatchMetricDisplay] = []
        values.append(BatchMetricDisplay(
            name: "综合响度", value: record.integratedLUFS.map { String(format: "%.1f LUFS", $0) } ?? "—",
            standard: "-16 ～ -12 LUFS", score: record.integratedLUFS.map { max(0, min(100, 100 - abs($0 + 14) * 8)) } ?? 0,
            level: record.failedChecks.contains("综合响度 LUFS") ? .fail : (record.reviewChecks.contains("综合响度 LUFS") ? .review : .pass)
        ))
        values.append(BatchMetricDisplay(
            name: "真峰", value: String(format: "%.2f dBTP", record.truePeakDb),
            standard: "≤ -1.0 dBTP", score: record.truePeakDb <= -1 ? 100 : max(0, 100 + record.truePeakDb * 35),
            level: record.truePeakDb > 0 ? .fail : (record.truePeakDb > -1 ? .review : .pass)
        ))
        values.append(BatchMetricDisplay(
            name: "削波", value: String(format: "%.4f%%", record.clippingPercent),
            standard: "≤ 0.001%", score: max(0, 100 - record.clippingPercent * 1200),
            level: record.clippingPercent > 0.05 ? .fail : (record.clippingPercent > 0.001 ? .review : .pass)
        ))
        values.append(BatchMetricDisplay(
            name: "动态余量", value: String(format: "%.1f dB", record.crestFactorDb),
            standard: "4.5 ～ 14 dB", score: max(0, min(100, 100 - abs(record.crestFactorDb - 9) * 9)),
            level: record.failedChecks.contains("动态余量 / 峰值因子") ? .fail : (record.reviewChecks.contains("动态余量 / 峰值因子") ? .review : .pass)
        ))
        if let phase = record.stereoCorrelation {
            values.append(BatchMetricDisplay(
                name: "相位相关性", value: String(format: "%.2f", phase),
                standard: "0.25 ～ 0.90", score: phase >= 0.25 && phase <= 0.90 ? 100 : max(0, 100 - abs(phase - 0.575) * 140),
                level: phase < 0.05 ? .fail : ((phase < 0.25 || phase > 0.90) ? .review : .pass)
            ))
        }
        if let balance = record.channelBalanceDb {
            values.append(BatchMetricDisplay(
                name: "左右电平差", value: String(format: "%+.2f dB", balance),
                standard: "≤ 1 dB", score: max(0, 100 - abs(balance) * 25),
                level: abs(balance) > 3 ? .fail : (abs(balance) > 1 ? .review : .pass)
            ))
        }
        if let fold = record.monoFoldDownLossDb {
            values.append(BatchMetricDisplay(
                name: "单声道折叠损失", value: String(format: "%.2f dB", fold),
                standard: "≥ -1 dB", score: max(0, min(100, 100 + fold * 18)),
                level: fold < -3 ? .fail : (fold < -1 ? .review : .pass)
            ))
        }
        if let spatial = record.spatialScore {
            values.append(BatchMetricDisplay(
                name: "空间展开指数", value: String(format: "%.0f / 100", spatial),
                standard: "≥ 70", score: spatial,
                level: spatial < 45 ? .fail : (spatial < 70 ? .review : .pass)
            ))
        }
        values.append(BatchMetricDisplay(
            name: "低频能量", value: String(format: "%.1f%%", record.lowEnergyPercent),
            standard: "15% ～ 50%", score: max(0, min(100, 100 - abs(record.lowEnergyPercent - 32) * 3)),
            level: record.lowEnergyPercent < 15 ? .review : .pass
        ))
        if let hiss = record.hissRatioDb {
            values.append(BatchMetricDisplay(
                name: "高频噪声", value: String(format: "%.1f dB", hiss),
                standard: "≤ -18 dB", score: max(0, min(100, (hiss + 25) * 7)),
                level: hiss > -12 ? .fail : (hiss > -18 ? .review : .pass)
            ))
        }
        if let ai = record.aiFeelScore {
            values.append(BatchMetricDisplay(
                name: "疑似 AI 感", value: String(format: "%.0f / 100", ai),
                standard: "≤ 35", score: 100 - ai,
                level: ai > 65 ? .fail : (ai > 35 ? .review : .pass)
            ))
        }
        if let key = record.musicKey {
            values.append(BatchMetricDisplay(
                name: "调式调性",
                value: key,
                standard: "仅作参考",
                score: (record.musicKeyConfidence ?? 0) * 100,
                level: (record.musicKeyConfidence ?? 0) < 0.45 ? .review : .pass
            ))
        }
        if let bpm = record.tempoBPM {
            values.append(BatchMetricDisplay(
                name: "节拍 BPM",
                value: String(format: "%.1f", bpm),
                standard: record.timeSignature ?? "节拍为估算",
                score: 100,
                level: .pass
            ))
        }
        if let lead = record.leadPart {
            values.append(BatchMetricDisplay(
                name: "主奏推测",
                value: lead,
                standard: "配器角色为启发式判断",
                score: (record.arrangementConfidence ?? 0) * 100,
                level: (record.arrangementConfidence ?? 0) < 0.45 ? .review : .pass
            ))
        }
        if let score = record.artifactOverall {
            values.append(BatchMetricDisplay(
                name: "AI 伪影总分", value: String(format: "%.0f / 100", score),
                standard: "≤ 45", score: 100 - score,
                level: score > 70 ? .fail : (score > 45 ? .review : .pass)
            ))
        }
        if let score = record.artifactHiss {
            values.append(BatchMetricDisplay(name: "沙声伪影", value: String(format: "%.0f", score), standard: "≤ 45", score: 100 - score, level: score > 70 ? .fail : (score > 45 ? .review : .pass)))
        }
        if let score = record.artifactShimmer {
            values.append(BatchMetricDisplay(name: "金属闪烁", value: String(format: "%.0f", score), standard: "≤ 45", score: 100 - score, level: score > 70 ? .fail : (score > 45 ? .review : .pass)))
        }
        if let score = record.artifactSpectralHole {
            values.append(BatchMetricDisplay(name: "频谱空洞", value: String(format: "%.0f", score), standard: "≤ 45", score: 100 - score, level: score > 70 ? .fail : (score > 45 ? .review : .pass)))
        }
        if let score = record.artifactTransientSmear {
            values.append(BatchMetricDisplay(name: "瞬态模糊", value: String(format: "%.0f", score), standard: "≤ 45", score: 100 - score, level: score > 70 ? .fail : (score > 45 ? .review : .pass)))
        }
        return values
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = record.error {
                Text("错误：\(error)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(metrics) { metric in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(metric.name).font(.caption)
                            Spacer()
                            Text(metric.value).font(.caption.weight(.semibold)).monospacedDigit()
                        }
                        ProgressView(value: Double(metric.score) / 100)
                        Text(metric.standard)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            if !record.failedChecks.isEmpty {
                Text("技术异常：\(record.failedChecks.joined(separator: "、"))")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if !record.reviewChecks.isEmpty {
                Text("建议复核：\(record.reviewChecks.joined(separator: "、"))")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if !record.issueIntervals.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("时间轴 Badcase 定位")
                        .font(.caption.weight(.semibold))
                    ForEach(record.issueIntervals.prefix(12)) { interval in
                        HStack(alignment: .top, spacing: 8) {
                            Text(String(format: "%.1f-%.1fs", interval.startTime, interval.endTime))
                                .font(.caption2.monospacedDigit())
                                .frame(width: 88, alignment: .leading)
                            Text(interval.severity)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(interval.severity == "高" ? .red : (interval.severity == "中" ? .orange : .secondary))
                                .frame(width: 24)
                            Text("\(interval.issue)：\(interval.evidence)。建议：\(interval.suggestedFix)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if record.issueIntervals.count > 12 {
                        Text("另有 \(record.issueIntervals.count - 12) 个窗口，详见 HTML 报告。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
            }
        }
    }
}

struct BatchMetricDisplay: Identifiable {
    var id: String { name }
    let name: String
    let value: String
    let standard: String
    let score: Float
    let level: LabelLevel
}

struct BatchSummaryCard: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.11), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct AnnotationDashboard: View {
    let report: AudioAnalysisReport

    private var assessment: LabelAssessment {
        LabelStandards.assess(report)
    }

    var body: some View {
        GroupBox("客观标注仪表盘") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(assessment.verdict)
                            .font(.title3.weight(.semibold))
                        Text("等级 \(assessment.grade) · 异常 \(assessment.failedNames.count) 项 / 复核 \(assessment.reviewNames.count) 项")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(assessment.grade)
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .frame(width: 68, height: 68)
                        .background(gradeColor.opacity(0.14), in: Circle())
                        .foregroundStyle(gradeColor)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(assessment.criteria) { criterion in
                        CriterionCard(criterion: criterion)
                    }
                }

                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("频段能量分布").font(.headline)
                        HStack(alignment: .bottom, spacing: 6) {
                            ForEach(report.bandEnergies) { band in
                                VStack(spacing: 4) {
                                    Text(String(format: "%.0f", band.energyPercent))
                                        .font(.caption2)
                                        .monospacedDigit()
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.accentColor.opacity(0.75))
                                        .frame(height: max(3, min(CGFloat(88), CGFloat(band.energyPercent * 2.4))))
                                    Text(band.name)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 42)
                                }
                            }
                        }
                    }
                    Spacer()
                }
            }
        }
    }

    private var gradeColor: Color {
        switch assessment.level {
        case .pass: return .green
        case .review: return .orange
        case .fail: return .red
        }
    }
}

struct CriterionCard: View {
    let criterion: LabelCriterion

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(criterion.category)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(levelColor.opacity(0.13), in: Capsule())
                    .foregroundStyle(levelColor)
                Spacer()
                Text(criterion.level.rawValue)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(levelColor)
            }
            Text(criterion.name).font(.headline)
            Text(criterion.value).font(.title3.weight(.semibold)).monospacedDigit()
            ProgressView(value: Double(criterion.score) / 100)
            Text(criterion.standard)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(criterion.interpretation)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private var levelColor: Color {
        switch criterion.level {
        case .pass: return .green
        case .review: return .orange
        case .fail: return .red
        }
    }
}

struct AnnotationStandardsSummary: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
            standard("综合响度", "-16 ～ -12 LUFS；越接近 -14 越适合流媒体分发")
            standard("真峰 / 削波", "真峰 ≤ -1.0 dBTP；削波采样 ≤ 0.001%")
            standard("动态余量", "峰值因子 4.5 ～ 14 dB；过低代表过度压缩，过高注意弱段可听性")
            standard("相位 / 单声道兼容", "相位相关性 0.25 ～ 0.90；折叠损失 ≥ -1 dB")
            standard("左右平衡", "左右声道 RMS 差 ≤ 1 dB；>3 dB 标为异常")
            standard("空间展开", "指数 ≥70；由立体声宽度和相位安全度组成，不代表听感优劣")
            standard("低频身体感", "20～350Hz 能量 15%～50%；过低提示薄、假")
            standard("高频噪声 / AI 感", "9kHz 以上占比 ≤ -18 dB；疑似 AI 感 ≤35")
            }
            Group {
            standard("AI 伪影七维", "沙声、金属闪烁、频谱空洞、偏薄、相位不稳、瞬态模糊、立体声异常：单项 ≤45，45～70 复核，>70 异常")
            standard("时间轴定位", "高严重度窗口判异常；两个以上中严重度窗口判复核；标注员优先试听定位区间")
            standard("音乐结构", "调性、BPM、拍号和配器主辅角色均为启发式推测；低置信度时必须人工确认")
            Text("这些指标用于减少主观听感偏差，不替代最终人工试听。")
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func standard(_ name: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.seal")
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.caption.weight(.semibold))
                Text(text).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
