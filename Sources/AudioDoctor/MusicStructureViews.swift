import SwiftUI

struct MusicStructureDashboard: View {
    let report: AudioAnalysisReport
    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        GroupBox("音乐结构分析：调式调性 / 节拍 / 配器角色") {
            VStack(alignment: .leading, spacing: 14) {
                if let structure = report.musicStructure {
                    HStack(alignment: .top, spacing: 12) {
                        MusicStructureMetricCard(
                            title: "调式调性",
                            value: structure.tonality?.bestKeyName ?? "未判断",
                            detail: structure.tonality.map { String(format: "置信度 %.0f%%", $0.confidence * 100) } ?? "音频太短或音高线索不足"
                        )
                        MusicStructureMetricCard(
                            title: "节拍 BPM",
                            value: structure.tempo.map { String(format: "%.1f", $0.bpm) } ?? "未判断",
                            detail: structure.tempo.map { String(format: "%@ · 置信度 %.0f%%", $0.timeSignatureEstimate, $0.confidence * 100) } ?? "节拍线索不足"
                        )
                        MusicStructureMetricCard(
                            title: "主奏推测",
                            value: structure.arrangement?.leadSummary ?? "未判断",
                            detail: structure.arrangement.map { String(format: "配器判断置信度 %.0f%%", $0.confidence * 100) } ?? "配器线索不足"
                        )
                        MusicStructureMetricCard(
                            title: "节拍周期",
                            value: structure.tempo.map { String(format: "%.3f 秒", $0.beatIntervalSeconds) } ?? "—",
                            detail: structure.tempo.map { "约 \($0.estimatedBeats) 拍 · Onset \($0.onsetDensityPerMinute)/分钟" } ?? "—"
                        )
                    }

                    if let tonality = structure.tonality {
                        pitchClassChart(tonality)
                        alternativeKeys(tonality)
                        Text(tonality.interpretation)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if let tempo = structure.tempo {
                        tempoCard(tempo)
                    }

                    if let arrangement = structure.arrangement {
                        arrangementCard(arrangement)
                    }
                } else {
                    Text("音频时长或音高线索不足，暂无法进行音乐结构分析。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func pitchClassChart(_ tonality: MusicTonalityAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("十二个音级的相对能量").font(.headline)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(tonality.pitchClassEnergy.enumerated()), id: \.offset) { item in
                    let value = item.element
                    VStack(spacing: 4) {
                        Text(String(format: "%.0f", value * 100))
                            .font(.caption2)
                            .monospacedDigit()
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isTonic(item.offset, tonality: tonality) ? Color.green : Color.accentColor.opacity(0.72))
                            .frame(height: max(3, min(CGFloat(78), CGFloat(value * 1000))))
                        Text(pitchName(item.offset))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 34)
                    }
                }
            }
        }
    }

    private func alternativeKeys(_ tonality: MusicTonalityAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("候选调性").font(.headline)
            ForEach(tonality.alternatives) { candidate in
                HStack {
                    Text(candidate.name).font(.caption)
                    Spacer()
                    Text(String(format: "相关度 %.2f · 置信度 %.0f%%", candidate.score, candidate.confidence * 100))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func tempoCard(_ tempo: MusicTempoAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("节拍与拍号推测").font(.headline)
                Spacer()
                Text(String(format: "拍号置信度 %.0f%%", tempo.timeSignatureConfidence * 100))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 14) {
                Label(String(format: "%.1f BPM", tempo.bpm), systemImage: "metronome")
                Label(tempo.timeSignatureEstimate, systemImage: "4.square")
                Label(String(format: "%.2f 秒/拍", tempo.beatIntervalSeconds), systemImage: "timer")
                Label(String(format: "%.0f Onset/分钟", tempo.onsetDensityPerMinute), systemImage: "waveform.path.ecg")
            }
            .font(.caption)
            Text(tempo.interpretation)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
    }

    private func arrangementCard(_ arrangement: MusicArrangementAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("配器与主辅角色").font(.headline)
                Spacer()
                Text(String(format: "整体置信度 %.0f%%", arrangement.confidence * 100))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ForEach(arrangement.parts) { part in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(part.name).font(.caption.weight(.semibold))
                        Text(part.role)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(roleColor(part.role).opacity(0.14), in: Capsule())
                            .foregroundStyle(roleColor(part.role))
                        Spacer()
                        Text(String(format: "%.0f%%", part.confidence * 100))
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: Double(part.confidence))
                    Text("\(part.evidence) · 相关线索强度约 \(String(format: "%.0f%%", part.energyPercent))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
            Text("边界说明：\(arrangement.interpretation)")
                .font(.caption2)
                .foregroundStyle(.orange)
        }
    }

    private func isTonic(_ index: Int, tonality: MusicTonalityAnalysis) -> Bool {
        tonality.tonicName == pitchName(index)
    }

    private func pitchName(_ index: Int) -> String {
        ["C", "C♯/D♭", "D", "D♯/E♭", "E", "F", "F♯/G♭", "G", "G♯/A♭", "A", "A♯/B♭", "B"][index]
    }

    private func roleColor(_ role: String) -> Color {
        if role.contains("主奏") { return .green }
        if role.contains("重要") || role.contains("基础") || role.contains("支撑") { return .orange }
        return .secondary
    }
}

struct MusicStructureMetricCard: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).lineLimit(2)
            Text(detail).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
    }
}
