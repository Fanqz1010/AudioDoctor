import SwiftUI

struct RepairStudioView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedCategory: RepairCategory = .overview

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            sidebar
            Divider()
            if let report = model.report {
                workArea(report)
            } else {
                WorkbenchEmptyState(
                    title: "先体检，再修复",
                    subtitle: "修复工作台会直接读取标注诊断结果，把沙声、偏薄、相位、瞬态和响度问题转成可理解的修复方案。",
                    actionTitle: "返回标注工作台"
                ) {
                    model.selectedWorkspace = "annotation"
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.98, green: 0.95, blue: 0.99),
                            Color(red: 0.94, green: 0.99, blue: 0.97)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.92))
                        .frame(width: 46, height: 46)
                    Text("🩺")
                        .font(.system(size: 22))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("修复小诊室")
                        .font(.headline)
                    Text("保守处理，先听效果")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            DropZone(title: "拖入要修复的音频", subtitle: "原始文件永远不会被覆盖") { url in
                model.loadFile(url: url)
            }
            DropZone(title: "可选：拖入参考曲", subtitle: "让“丰满度”更接近目标风格") { url in
                model.loadReference(url: url)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("修复步骤")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(RepairCategory.allCases) { category in
                    Button {
                        selectedCategory = category
                    } label: {
                        HStack(spacing: 10) {
                            Text(category.emoji)
                                .font(.system(size: 17))
                                .frame(width: 28, height: 28)
                                .background(category.color.opacity(0.14), in: Circle())
                            VStack(alignment: .leading, spacing: 1) {
                                Text(category.title).font(.callout.weight(.medium))
                                Text(category.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 6)
                        .background(
                            selectedCategory == category
                                ? category.color.opacity(0.13)
                                : Color.white.opacity(0.72),
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                model.selectedWorkspace = "annotation"
            } label: {
                Label("回到标注工作台", systemImage: "arrow.left.circle")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 270)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.97, green: 0.94, blue: 0.99),
                    Color(red: 0.92, green: 0.98, blue: 0.96)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func workArea(_ report: AudioAnalysisReport) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    cuteHeader(report)

                    repairSection(.overview) {
                        RepairOverviewCard(report: report, after: model.processedReport)
                    }

                    repairSection(.plan) {
                        RepairPlanCard(report: report)
                        repairControls
                    }

                    repairSection(.spatial) {
                        spatialCard
                    }

                    repairSection(.result) {
                        RepairResultCard(before: report, after: model.processedReport)
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: selectedCategory) { category in
                withAnimation(.easeInOut(duration: 0.22)) {
                    proxy.scrollTo(category.rawValue, anchor: .top)
                }
            }
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.99, green: 0.98, blue: 1.00),
                    Color(red: 0.96, green: 0.99, blue: 0.98)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func cuteHeader(_ report: AudioAnalysisReport) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("🎵 修复工作台")
                    .font(.title2.weight(.semibold))
                Text("诊断结果会同步到修复步骤；每一项都能看见为什么修、修哪里、修完变化多少。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isWorking {
                ProgressView()
            } else {
                Button {
                    model.processAndExport()
                } label: {
                    Label("开始修复并导出", systemImage: "wand.and.stars")
                }
                .controlSize(.large)
                .disabled(!model.isBetaUnlocked)
                .help(model.isBetaUnlocked ? "导出到新文件" : "修复导出仍在内测")
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.pink.opacity(0.12), lineWidth: 1))
    }

    private func repairSection<Content: View>(_ category: RepairCategory, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 11) {
                Text(category.emoji)
                    .font(.system(size: 19))
                    .frame(width: 36, height: 36)
                    .background(category.color.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title).font(.title3.weight(.semibold))
                    Text(category.subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
            }
            content()
        }
        .id(category.rawValue)
        .padding(16)
        .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 18))
        .overlay(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18)
                .fill(category.color.opacity(0.20))
                .frame(width: 5)
                .padding(.vertical, 14)
        }
        .shadow(color: Color.black.opacity(0.025), radius: 8, y: 4)
    }

    private var repairControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("内容预设", selection: $model.repair.presetRawValue) {
                ForEach(ContentPreset.allCases) { preset in
                    Text(preset.title).tag(preset.rawValue)
                }
            }
            Text(model.repair.preset.summary)
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
    repairToggle("去高频沙沙声", isOn: $model.repair.deHiss)
                repairToggle("补低频身体感", isOn: $model.repair.fullness)
                repairToggle("低频相位稳定", isOn: $model.repair.lowFrequencyMono)
                repairToggle("瞬态恢复", isOn: $model.repair.transientRecovery)
                repairToggle("空气感 / 细节", isOn: $model.repair.exciter)
                repairToggle("响度标准化", isOn: $model.repair.loudnessNormalize)
            }

            Toggle("使用参考曲匹配频响", isOn: $model.repair.matchReference)
                .disabled(model.referenceURL == nil)

            HStack {
                Text("目标响度")
                TextField("-14", value: $model.repair.targetLUFS, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                Text("LUFS")
                Spacer()
                Text("真峰保护")
                Text("≤ -1 dBTP")
                    .foregroundStyle(.green)
            }

            HStack {
                Text("修复强度")
                Slider(value: $model.repair.strength, in: 0...1.5, step: 0.1)
                Text(String(format: "%.1f", model.repair.strength))
                    .monospacedDigit()
                    .frame(width: 34)
            }

            HStack {
                Button {
                    model.applySunoRecommendedSettings(vocalFocus: true)
                } label: {
                    Label("Suno 人声", systemImage: "person.wave.2")
                }
                Button {
                    model.applySunoRecommendedSettings(vocalFocus: false)
                } label: {
                    Label("Suno 流行", systemImage: "music.note")
                }
                Spacer()
            }

            if let message = model.message {
                Label(message, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 16))
    }

    private func repairToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
    }

    private var spatialCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            Picker("导出声道", selection: $model.channelTarget) {
                Text("保持原样").tag("keep")
                Text("立体声 → 单声道").tag("mono")
                Text("单声道 → 立体声").tag("stereo")
                Text("立体声 → 5.1").tag("surround51")
                Text("立体声 → AmbiX").tag("ambix")
            }
            .pickerStyle(.radioGroup)

            HStack {
                Picker("格式", selection: $model.outputFormat) {
                    Text("WAV").tag("wav")
                    Text("AIFF").tag("aiff")
                }
                .frame(width: 120)
                Picker("位深", selection: $model.bitDepth) {
                    Text("16-bit").tag(16)
                    Text("24-bit").tag(24)
                }
                .frame(width: 120)
                Spacer()
            }

            if model.channelTarget == "surround51" {
                Label("输出 6 声道：L、R、C、LFE、Ls、Rs", systemImage: "speaker.wave.3")
                    .font(.caption)
            } else if model.channelTarget == "ambix" {
                VStack(alignment: .leading, spacing: 4) {
                    Label("输出一阶 AmbiX：W、Y、Z、X（ACN/SN3D）", systemImage: "globe.asia.australia")
                        .font(.caption)
                    Text("这是开源空间音频格式，不是 Dolby Atmos 母版。")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            } else {
                Label("转换会先做安全相位处理提示；原始文件不会被覆盖。", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct RepairOverviewCard: View {
    let report: AudioAnalysisReport
    let after: AudioAnalysisReport?

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                CategoryPill(text: "AI 伪影 \(Int(report.artifactScores?.overall ?? 0))", color: scoreColor(report.artifactScores?.overall ?? 0))
                CategoryPill(text: report.distortionRisk, color: report.distortionRisk.hasPrefix("低") ? .green : .orange)
                CategoryPill(text: report.phaseRisk, color: report.phaseRisk.hasPrefix("正常") ? .green : .orange)
                Spacer()
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
                cuteMetric("响度", report.integratedLUFS.map { String(format: "%.1f LUFS", $0) } ?? "—")
                cuteMetric("真峰", String(format: "%.1f dBTP", report.truePeakDb))
                cuteMetric("宽度", report.stereoWidthPercent.map { String(format: "%.0f%%", $0) } ?? "单声道")
                cuteMetric("时长", String(format: "%.1f 秒", report.durationSeconds))
            }
            Text("修复策略：先降噪，再补身体感，然后处理相位与瞬态，最后标准化响度并做真峰保护。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 16))
    }

    private func cuteMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.97, green: 0.95, blue: 1.0), in: RoundedRectangle(cornerRadius: 12))
    }

    private func scoreColor(_ score: Float) -> Color {
        score <= 45 ? .green : (score <= 70 ? .orange : .red)
    }
}

struct RepairPlanCard: View {
    let report: AudioAnalysisReport

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let scores = report.artifactScores {
                ForEach(Array(scores.ranked.prefix(7)), id: \.name) { item in
                    HStack(spacing: 10) {
                        CategoryPill(text: item.name, color: scoreColor(item.score))
                        Text(repairAdvice(item.name))
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Text(String(format: "%.0f", item.score))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(scoreColor(item.score))
                    }
                    .padding(9)
                    .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 11))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 16))
    }

    private func repairAdvice(_ name: String) -> String {
        if name.contains("沙") || name.contains("高频") { return "先做高频伪影抑制，再考虑空气感。" }
        if name.contains("薄") { return "补 55–260Hz 身体感，必要时用参考曲匹配。" }
        if name.contains("空洞") { return "按内容预设修补中低频 / 中高频空洞。" }
        if name.contains("相位") || name.contains("立体声") { return "低频单声道化，降低单声道播放抵消风险。" }
        if name.contains("瞬态") { return "恢复鼓点与辅音边界，避免更强压缩。" }
        if name.contains("闪烁") || name.contains("金属") { return "降低 6–12kHz 过量增益，保留少量明亮度。" }
        return "保持保守处理，优先保护原有音色。"
    }

    private func scoreColor(_ score: Float) -> Color {
        score <= 45 ? .green : (score <= 70 ? .orange : .red)
    }
}

struct RepairResultCard: View {
    let before: AudioAnalysisReport
    let after: AudioAnalysisReport?

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            if let after {
                comparison("AI 伪影总分", before: before.artifactScores?.overall, after: after.artifactScores?.overall, lowerIsBetter: true)
                comparison("综合响度", before: before.integratedLUFS, after: after.integratedLUFS)
                comparison("真峰", before: before.truePeakDb, after: after.truePeakDb)
                Text("导出时同时生成 `.report.json`，记录修复参数与前后指标，方便复核或给客户交付。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Label("还没有修复结果", systemImage: "sparkles")
                        .font(.headline)
                    Text("选择修复方案后点击“开始修复并导出”。完成后这里会展示前后对比。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 16))
    }

    private func comparison(_ title: String, before: Float?, after: Float?, lowerIsBetter: Bool = false) -> some View {
        HStack {
            Text(title).frame(width: 120, alignment: .leading)
            Text(before.map { String(format: "%.1f", $0) } ?? "—")
                .monospacedDigit()
                .frame(width: 70, alignment: .trailing)
                .foregroundStyle(.secondary)
            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(after.map { String(format: "%.1f", $0) } ?? "—")
                .monospacedDigit()
                .fontWeight(.semibold)
                .frame(width: 70, alignment: .leading)
            Spacer()
            if let b = before, let a = after {
                let delta = a - b
                let improved = lowerIsBetter ? delta < 0 : (title == "真峰" ? a <= -1 && a >= b : abs(a + 14) < abs(b + 14))
                CategoryPill(text: String(format: "%+.1f", delta), color: improved ? .green : .orange)
            }
        }
        .font(.callout)
    }
}
