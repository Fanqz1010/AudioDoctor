import SwiftUI

struct ContentOptimizationWorkspaceView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    DropZone(
                        title: "拖入要优化的音乐 / 音频",
                        subtitle: "内容优化基于当前文件的技术诊断执行"
                    ) { url in
                        model.loadFile(url: url)
                    }

                    GroupBox("内容预设") {
                        Picker("风格", selection: $model.repair.presetRawValue) {
                            ForEach(ContentPreset.allCases) { preset in
                                Text(preset.title).tag(preset.rawValue)
                            }
                        }
                        .pickerStyle(.radioGroup)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.repair.preset.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("预设不是“更响更好”的魔法按钮：它改变频段、低频相位和瞬态策略，处理后仍需 A/B 试听。")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    GroupBox("按需求优化") {
                        Toggle("低频与身体感补偿", isOn: $model.repair.fullness)
                        Toggle("低频单声道化 / 稳定低频声像", isOn: $model.repair.lowFrequencyMono)
                        Toggle("瞬态恢复 / 改善鼓点攻击力", isOn: $model.repair.transientRecovery)
                        Toggle("空气感与细节增强", isOn: $model.repair.exciter)
                        Toggle("响度标准化", isOn: $model.repair.loudnessNormalize)
                        HStack {
                            Text("目标响度")
                            TextField("-14", value: $model.repair.targetLUFS, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                            Text("LUFS")
                        }
                        HStack {
                            Text("优化强度")
                            Slider(value: $model.repair.strength, in: 0...1.5, step: 0.1)
                            Text(String(format: "%.1f", model.repair.strength))
                                .monospacedDigit()
                                .frame(width: 30)
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
                            Label("优化并导出新文件", systemImage: "slider.horizontal.3")
                                .frame(maxWidth: .infinity)
                        }
                        .controlSize(.large)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(model.inputURL == nil)
                        Text("原始文件不会被覆盖。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if model.isWorking { ProgressView("正在处理…") }
                    if let message = model.message {
                        Label(message, systemImage: "checkmark.circle").foregroundStyle(.green)
                    }
                    if let error = model.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    }
                }
            }
            .frame(width: 380)

            if let report = model.report {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        GroupBox("内容优化方案") {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(model.repair.preset.title).font(.title3.weight(.semibold))
                                ForEach(optimizationPlan(report), id: \.self) { line in
                                    Label(line, systemImage: "circle.dotted")
                                        .font(.caption)
                                }
                            }
                        }

                        if let scores = report.artifactScores {
                            GroupBox("优化前后重点") {
                                VStack(alignment: .leading, spacing: 12) {
                                    ForEach(scores.ranked.prefix(4), id: \.name) { item in
                                        HStack {
                                            Text(item.name).font(.caption)
                                            Spacer()
                                            Text(String(format: "%.0f / 100", item.score))
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(item.score <= 45 ? .green : (item.score <= 70 ? .orange : .red))
                                        }
                                    }
                                }
                            }
                        }

                        if let structure = report.musicStructure {
                            GroupBox("音乐结构参考") {
                                VStack(alignment: .leading, spacing: 8) {
                                    if let tonality = structure.tonality {
                                        Label("调性：\(tonality.bestKeyName) · 置信度 \(String(format: "%.0f%%", tonality.confidence * 100))", systemImage: "music.quarternote.3")
                                    }
                                    if let tempo = structure.tempo {
                                        Label(String(format: "节拍：%.1f BPM · %@", tempo.bpm, tempo.timeSignatureEstimate), systemImage: "metronome")
                                    }
                                    if let arrangement = structure.arrangement {
                                        Label("主奏推测：\(arrangement.leadSummary)", systemImage: "person.wave.2")
                                    }
                                    Text("调性、BPM 与配器角色是本地启发式分析，仅用于辅助判断内容风格，不等同于乐谱结论。")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .font(.caption)
                            }
                        }

                        GroupBox("导出检查") {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("目标响度：\(String(format: "%.1f LUFS", model.repair.targetLUFS))", systemImage: "speaker.wave.2")
                                Label("峰值安全：≤ -1.0 dBTP", systemImage: "waveform.path")
                                Label("兼容性：低频相位稳定后单声道折叠更安全", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .font(.caption)
                        }

                        if let processed = model.processedReport {
                            GroupBox("优化结果") {
                                VStack(alignment: .leading, spacing: 8) {
                                    comparison("AI 伪影总分", before: report.artifactScores?.overall, after: processed.artifactScores?.overall)
                                    comparison("综合响度", before: report.integratedLUFS, after: processed.integratedLUFS)
                                    comparison("真峰", before: report.truePeakDb, after: processed.truePeakDb)
                                }
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 54))
                        .foregroundStyle(.secondary)
                    Text("拖入音频后，Audio Doctor 会先诊断，再给出内容优化策略")
                        .font(.headline)
                    Text("适合 Suno 生成曲、流行歌、电子乐、影视配乐和播客的差异化处理")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func optimizationPlan(_ report: AudioAnalysisReport) -> [String] {
        var lines: [String] = []
        if let scores = report.artifactScores {
            if scores.hiss > 45 { lines.append("先抑制高频稳态伪影，再做任何空气感增强。") }
            if scores.thinness > 45 { lines.append("补 55–260Hz 身体感；若有参考曲，优先使用参考曲带状匹配。") }
            if scores.spectralHole > 45 { lines.append("用 \(model.repair.preset.title) 预设修补中低频/中高频空洞。") }
            if scores.phaseInstability > 45 || scores.stereoAnomaly > 45 { lines.append("开启低频单声道化，降低单声道播放抵消风险。") }
            if scores.transientSmear > 45 { lines.append("开启瞬态恢复，让鼓组和人声辅音边界更清楚。") }
        }
        if let lufs = report.integratedLUFS, lufs < -16 || lufs > -12 {
            lines.append("响度偏离常用分发区间，导出时标准化到 \(String(format: "%.0f", model.repair.targetLUFS)) LUFS。")
        }
        if lines.isEmpty { lines.append("技术风险较低：保持轻量优化，重点保护原有动态和音色个性。") }
        return lines
    }

    private func comparison(_ title: String, before: Float?, after: Float?) -> some View {
        HStack {
            Text(title).font(.caption)
            Spacer()
            Text(before.map { String(format: "%.1f", $0) } ?? "—").monospacedDigit().foregroundStyle(.secondary)
            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
            Text(after.map { String(format: "%.1f", $0) } ?? "—").monospacedDigit().fontWeight(.semibold)
        }
    }
}
