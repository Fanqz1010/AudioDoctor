import SwiftUI

struct AnnotationWorkbenchView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedCategory: WorkbenchCategory = .content

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            sidebar
            Divider()
            if let report = model.report {
                workArea(report)
            } else {
                WorkbenchEmptyState(
                    title: "拖入音频，开始标注体检",
                    subtitle: "标注员模式只读原始文件：先判断内容类型，再看音乐结构、技术质量、时间定位，最后确认标注结论。",
                    actionTitle: model.inputURL == nil ? "请拖入音频" : "重新分析"
                ) {
                    if let url = model.inputURL { model.loadFile(url: url) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.55))
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            DropZone(
                title: "拖入待标注音频",
                subtitle: "只读分析，不修改原始文件"
            ) { url in
                model.loadFile(url: url)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("标注大类")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(WorkbenchCategory.allCases) { category in
                    Button {
                        selectedCategory = category
                    } label: {
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(category.color)
                                .frame(width: 5, height: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(category.step) \(category.title)")
                                    .font(.callout.weight(.medium))
                                Text(category.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .background(
                            selectedCategory == category
                                ? category.color.opacity(0.11)
                                : Color(nsColor: .controlBackgroundColor).opacity(0.65),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if let report = model.report {
                Button {
                    model.selectedWorkspace = "repair"
                } label: {
                    Label("带诊断结果去修复", systemImage: "arrow.right.circle")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .disabled(!model.isBetaUnlocked)
                .help(model.isBetaUnlocked ? "切到修复工作台" : "修复导出仍在内测，请先开启内测权限")

                VStack(alignment: .leading, spacing: 6) {
                    Label(report.filename, systemImage: "music.note")
                        .font(.caption)
                        .lineLimit(1)
                    Label(String(format: "%.1f 秒 · %d 声道", report.durationSeconds, report.channels), systemImage: "clock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Label("标注员模式：不导出、不修复", systemImage: "lock.shield")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 270)
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.55))
    }

    private func workArea(_ report: AudioAnalysisReport) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    summaryHeader(report)

                    section(.content) {
                        MusicContentTypeCard(content: report.musicStructure?.contentType)
                    }

                    section(.structure) {
                        MusicStructureDashboard(report: report)
                        MusicTimelineCard(changes: report.musicStructure?.timelineChanges ?? [])
                        ChordFunctionCard(chords: report.musicStructure?.chordSegments ?? [])
                    }

                    section(.quality) {
                        AnnotationDashboard(report: report)
                    }

                    section(.timeline) {
                        AnnotationIssueTimeline(report: report)
                    }

                    section(.conclusion) {
                        AnnotationConclusionCard(report: report) {
                            model.selectedWorkspace = "repair"
                        }
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
    }

    private func summaryHeader(_ report: AudioAnalysisReport) -> some View {
        let assessment = LabelStandards.assess(report)
        return HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("标注工作台")
                    .font(.title2.weight(.semibold))
                Text("五个大类固定不变：内容 → 结构 → 质量 → 定位 → 确认。低置信度结果必须人工复核。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                CategoryPill(text: assessment.verdict, color: gradeColor(assessment.level))
                HStack(spacing: 7) {
                    CategoryPill(text: "异常 \(assessment.failedNames.count)", color: .red)
                    CategoryPill(text: "复核 \(assessment.reviewNames.count)", color: .orange)
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
    }

    private func section<Content: View>(_ category: WorkbenchCategory, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            WorkbenchSectionHeader(category: category)
            content()
        }
        .id(category.rawValue)
        .padding(16)
        .background(category.color.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(category.color.opacity(0.42))
                .frame(height: 2)
        }
    }

    private func gradeColor(_ level: LabelLevel) -> Color {
        switch level {
        case .pass: return .green
        case .review: return .orange
        case .fail: return .red
        }
    }
}

struct MusicContentTypeCard: View {
    let content: MusicContentTypeAnalysis?

    var body: some View {
        WorkbenchCard(
            title: "内容类型判断",
            caption: "决定这条音频应进入音乐标注、语音标注还是通用质检流程",
            accent: WorkbenchCategory.content.color
        ) {
            if let content {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    MusicStructureMetricCard(
                        title: "是否音乐",
                        value: content.isMusic ? "是" : "否 / 待复核",
                        detail: String(format: "音乐线索置信度 %.0f%%", content.musicConfidence * 100)
                    )
                    MusicStructureMetricCard(
                        title: "人声状态",
                        value: content.vocalState,
                        detail: String(format: "人声线索置信度 %.0f%%", content.vocalConfidence * 100)
                    )
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("判断依据").font(.caption.weight(.semibold))
                    ForEach(content.evidence, id: \.self) { item in
                        Label(item, systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("说明：这是混合音频启发式判断；说唱、和声、电子人声和器乐拟人声容易混淆，建议人工复核低置信度结果。")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            } else {
                Text("音频过短或信号不足，暂无法判断内容类型。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct MusicTimelineCard: View {
    let changes: [MusicTimelineChange]

    var body: some View {
        WorkbenchCard(
            title: "转调 / 节拍变化时间轴",
            caption: "自动定位疑似变化段落，边界和类型需人工确认",
            accent: WorkbenchCategory.structure.color
        ) {
            if changes.isEmpty {
                Label("未发现稳定的转调、速度或拍号变化", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 9) {
                    ForEach(changes) { change in
                        HStack(alignment: .top, spacing: 10) {
                            CategoryPill(text: change.type, color: change.type.contains("拍") ? .orange : .purple)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(timeRange(change))
                                    .font(.caption.weight(.semibold))
                                Text("\(change.fromValue) → \(change.toValue)")
                                    .font(.caption)
                                Text(change.note)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(String(format: "%.0f%%", change.confidence * 100))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(9)
                        .background(Color(nsColor: .windowBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }

    private func timeRange(_ change: MusicTimelineChange) -> String {
        String(format: "%.1f – %.1f 秒", change.startTime, change.endTime)
    }
}

struct ChordFunctionCard: View {
    let chords: [MusicChordSegment]

    var body: some View {
        WorkbenchCard(
            title: "和弦进行与功能",
            caption: "近似识别和弦、级数和 T / S / D 功能，不等于精确乐谱",
            accent: WorkbenchCategory.structure.color
        ) {
            if chords.isEmpty {
                Label("音频过短或和声信息不足，暂无法给出和弦推测", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("时间").frame(width: 110, alignment: .leading)
                        Text("和弦").frame(width: 70, alignment: .leading)
                        Text("级数").frame(width: 70, alignment: .leading)
                        Text("功能").frame(width: 140, alignment: .leading)
                        Spacer()
                        Text("置信度").frame(width: 56, alignment: .trailing)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    Divider()
                    ForEach(chords.prefix(40)) { chord in
                        HStack {
                            Text(String(format: "%.1f–%.1fs", chord.startTime, chord.endTime))
                                .frame(width: 110, alignment: .leading)
                            Text(chord.chord).frame(width: 70, alignment: .leading)
                            Text(chord.romanNumeral).frame(width: 70, alignment: .leading)
                            Text(chord.function).frame(width: 140, alignment: .leading)
                            Spacer()
                            Text(String(format: "%.0f%%", chord.confidence * 100))
                                .frame(width: 56, alignment: .trailing)
                        }
                        .font(.caption.monospacedDigit())
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        Divider()
                    }
                }
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
                if chords.count > 40 {
                    Text("仅预览前 40 段；完整结果会写入 JSON / 批量报告。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct AnnotationIssueTimeline: View {
    let report: AudioAnalysisReport

    var body: some View {
        WorkbenchCard(
            title: "问题时间定位",
            caption: "按严重程度排序，标注员优先试听高置信度区间",
            accent: WorkbenchCategory.timeline.color
        ) {
            if report.issueIntervals.isEmpty {
                Label("未定位到明显问题区间", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 9) {
                    ForEach(report.issueIntervals.prefix(24)) { interval in
                        HStack(alignment: .top, spacing: 10) {
                            CategoryPill(text: interval.severity, color: severityColor(interval.severity))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(String(format: "%.1f – %.1f 秒 · %@", interval.startTime, interval.endTime, interval.issue))
                                    .font(.caption.weight(.semibold))
                                Text(interval.evidence)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("建议：\(interval.suggestedFix)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(String(format: "%.0f%%", interval.confidence * 100))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(9)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                    }
                    if report.issueIntervals.count > 24 {
                        Text("其余 \(report.issueIntervals.count - 24) 个区间见完整报告。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func severityColor(_ severity: String) -> Color {
        switch severity {
        case "高": return .red
        case "中": return .orange
        default: return .blue
        }
    }
}

struct AnnotationConclusionCard: View {
    let report: AudioAnalysisReport
    var onRepair: () -> Void

    var body: some View {
        let assessment = LabelStandards.assess(report)
        WorkbenchCard(
            title: "标确切认与流转",
            caption: "自动结果只是建议，最终结论由标注员确认",
            accent: WorkbenchCategory.conclusion.color
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    CategoryPill(text: assessment.grade, color: gradeColor(assessment.level))
                    CategoryPill(text: assessment.verdict, color: gradeColor(assessment.level))
                    Spacer()
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    conclusionBlock("异常项", value: assessment.failedNames.isEmpty ? "无" : assessment.failedNames.joined(separator: "、"))
                    conclusionBlock("复核项", value: assessment.reviewNames.isEmpty ? "无" : assessment.reviewNames.joined(separator: "、"))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("标注建议").font(.caption.weight(.semibold))
                    ForEach(report.recommendations, id: \.self) { item in
                        Label(item, systemImage: "checkmark.seal")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button(action: onRepair) {
                        Label("转入修复工作台", systemImage: "wand.and.stars")
                    }
                    .controlSize(.large)
                    Spacer()
                    Text("标注员模式不导出原始音频，不覆盖原始文件。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func conclusionBlock(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.75), in: RoundedRectangle(cornerRadius: 10))
    }

    private func gradeColor(_ level: LabelLevel) -> Color {
        switch level {
        case .pass: return .green
        case .review: return .orange
        case .fail: return .red
        }
    }
}
