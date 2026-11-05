import Foundation

/// Transparent heuristic indicators for common audible problems in generated or restored audio.
/// They are not a claim about provenance and must not be used as a detection-evasion tool.
struct ArtifactScores: Codable, Equatable {
    var hiss: Float
    var shimmer: Float
    var spectralHole: Float
    var thinness: Float
    var phaseInstability: Float
    var transientSmear: Float
    var stereoAnomaly: Float
    var overall: Float

    var ranked: [(name: String, score: Float)] {
        [
            ("高频沙沙声", hiss),
            ("金属感 / 闪烁感", shimmer),
            ("频谱空洞", spectralHole),
            ("频段偏薄", thinness),
            ("相位不稳定", phaseInstability),
            ("瞬态模糊", transientSmear),
            ("立体声异常", stereoAnomaly)
        ]
        .sorted { $0.1 > $1.1 }
    }
}

struct IssueInterval: Codable, Identifiable, Equatable {
    var id: String { "\(Int(startTime * 1000))-\(issue)" }
    let startTime: Double
    let endTime: Double
    let issue: String
    let severity: String
    let confidence: Float
    let evidence: String
    let suggestedFix: String
}

enum ArtifactAnalyzer {
    static func score(
        channels: [[Float]],
        sampleRate: Float,
        spectrum: [(frequency: Float, powerDb: Float)],
        flatness: Float?,
        lowEnergyPercent: Float,
        hissRatioDb: Float,
        stereoCorrelation: Float?,
        channelBalanceDb: Float?,
        monoFoldDownLossDb: Float?
    ) -> ArtifactScores {
        let hiss = normalize(value: hissRatioDb, low: -26, high: -9)
        let highAir = spectrum.filter { $0.frequency >= 5500 && $0.frequency < 16000 }
            .map { pow(10, $0.powerDb / 10) }
            .reduce(0, +)
        let allEnergy = spectrum.map { pow(10, $0.powerDb / 10) }.reduce(0, +)
        let highRatio = allEnergy > 0 ? highAir / allEnergy : 0
        let flat = flatness ?? 0
        let shimmer = clamp01(highRatio / 0.28) * 0.58 + clamp01((flat - 0.04) / 0.36) * 0.42
        let hole = spectralHoleScore(spectrum: spectrum)
        let thin = clamp01((30 - lowEnergyPercent) / 30 * 100)
        let phase = phaseInstabilityScore(channels: channels)
        let smear = transientSmearScore(channels: channels)

        let balance = abs(channelBalanceDb ?? 0)
        let fold = abs(min(0, monoFoldDownLossDb ?? 0))
        let corr = stereoCorrelation ?? 0.55
        let stereoAnomaly = clamp01(balance / 5) * 0.28 + clamp01(fold / 7) * 0.37 +
            (corr < 0.15 ? 35 : (corr < 0.3 ? 20 : 0))

        let overall = hiss * 0.20 + shimmer * 0.17 + hole * 0.13 + thin * 0.18 +
            phase * 0.10 + smear * 0.10 + stereoAnomaly * 0.12
        return ArtifactScores(
            hiss: hiss,
            shimmer: shimmer,
            spectralHole: hole,
            thinness: thin,
            phaseInstability: phase,
            transientSmear: smear,
            stereoAnomaly: stereoAnomaly,
            overall: overall
        )
    }

    /// Return chronological badcase intervals. Adjacent equal-issue detections are merged.
    static func locateIssues(channels: [[Float]], sampleRate: Float, mono: Bool) -> [IssueInterval] {
        guard sampleRate > 0, channels.count > 0, let count = channels.map(\.count).min(), count > 0 else { return [] }
        let windowSeconds: Double = 4
        let windowFrames = max(1024, Int(sampleRate * Float(windowSeconds)))
        var found: [IssueInterval] = []
        var start = 0

        while start < count {
            let end = min(count, start + windowFrames)
            let windowChannels = channels.map { Array($0[start..<end]) }
            let left = windowChannels[0]
            let right = mono ? left : (windowChannels.count > 1 ? windowChannels[1] : left)
            let leftRmsDb = DSP.db(DSP.rms(left))
            let rightRmsDb = DSP.db(DSP.rms(right))
            let rmsDb = max(leftRmsDb, rightRmsDb)
            let startTime = Double(start) / Double(sampleRate)
            let endTime = Double(end) / Double(sampleRate)

            func append(_ issue: String, severity: String, confidence: Float, evidence: String, fix: String) {
                found.append(IssueInterval(
                    startTime: startTime,
                    endTime: endTime,
                    issue: issue,
                    severity: severity,
                    confidence: confidence,
                    evidence: evidence,
                    suggestedFix: fix
                ))
            }

            if rmsDb < -55 {
                append("接近静音", severity: "中", confidence: 0.90, evidence: "窗口 RMS \(String(format: "%.1f", rmsDb)) dBFS", fix: "确认是否为预期留白；非预期则检查源文件或生成参数。")
            } else {
                var clipped = 0
                for channel in windowChannels {
                    for sample in channel where abs(sample) >= 0.998 { clipped += 1 }
                }
                let clippingPercent = Float(clipped) / Float(max(1, (end - start) * windowChannels.count)) * 100
                if clippingPercent > 0.01 {
                    append("削波 / 失真", severity: clippingPercent > 0.1 ? "高" : "中", confidence: 0.94, evidence: String(format: "削波采样 %.3f%%", clippingPercent), fix: "降低上游增益，导出时保留 -1 dBTP 真峰限制。")
                }

                if !mono {
                    let corr = DSP.correlation(left, right)
                    let leftRms = DSP.rms(left)
                    let rightRms = DSP.rms(right)
                    let balance = DSP.db(leftRms / max(rightRms, 1e-9))
                    if let corr, corr < 0.1 {
                        append("相位风险", severity: corr < -0.1 ? "高" : "中", confidence: 0.86, evidence: String(format: "窗口相位相关 %.2f", corr), fix: "开启低频单声道化；单声道导出前必须复核。")
                    }
                    if abs(balance) > 4 {
                        append("左右不平衡", severity: abs(balance) > 7 ? "高" : "中", confidence: 0.82, evidence: String(format: "左右 RMS 差 %.1f dB", balance), fix: "检查声像或生成声道渲染，必要时做声道平衡。")
                    }
                }

                if end - start >= 2048 {
                    let fftSize = end - start >= 4096 ? 4096 : 2048
                    let localSpectrum = DSP.averageSpectrum(channels: windowChannels, sampleRate: sampleRate, fftSize: fftSize, maxFrames: 4)
                    if !localSpectrum.isEmpty {
                        let energy = localSpectrum.map { pow(10, $0.powerDb / 10) }.reduce(0, +)
                        let low = localSpectrum.filter { $0.frequency >= 20 && $0.frequency < 350 }
                            .map { pow(10, $0.powerDb / 10) }.reduce(0, +)
                        let high = localSpectrum.filter { $0.frequency >= 9000 }
                            .map { pow(10, $0.powerDb / 10) }.reduce(0, +)
                        let lowPercent = energy > 0 ? low / energy * 100 : 0
                        let highRatioDb = energy > 0 ? DSP.db(sqrt(high / energy)) : -120
                        if lowPercent < 10 {
                            append("频段偏薄", severity: lowPercent < 5 ? "高" : "中", confidence: 0.70, evidence: String(format: "20–350Hz 能量 %.1f%%", lowPercent), fix: "使用身体感补偿或同风格参考曲匹配。")
                        }
                        if highRatioDb > -12 {
                            append("高频伪影 / 沙沙声", severity: highRatioDb > -9 ? "高" : "中", confidence: 0.72, evidence: String(format: "9kHz 以上占比 %.1f dB", highRatioDb), fix: "开启高频伪影抑制，处理后 A/B 试听瞬态。")
                        }
                        let hole = spectralHoleScore(spectrum: localSpectrum)
                        if hole > 58 {
                            append("频谱空洞", severity: hole > 75 ? "高" : "中", confidence: 0.63, evidence: String(format: "局部空洞指数 %.0f / 100", hole), fix: "用内容预设或参考曲匹配补齐缺失频段。")
                        }
                    }
                }
            }
            start = end
        }

        // Merge adjacent windows that have the same issue, keeping the strongest severity/evidence.
        var merged: [IssueInterval] = []
        for interval in found {
            if let last = merged.last,
               last.issue == interval.issue,
               abs(last.endTime - interval.startTime) < 0.001 {
                let severityOrder = ["低": 0, "中": 1, "高": 2]
                let strongest = severityOrder[last.severity] ?? 0 >= (severityOrder[interval.severity] ?? 0) ? last : interval
                merged[merged.count - 1] = IssueInterval(
                    startTime: last.startTime,
                    endTime: interval.endTime,
                    issue: last.issue,
                    severity: strongest.severity,
                    confidence: max(last.confidence, interval.confidence),
                    evidence: strongest.evidence,
                    suggestedFix: strongest.suggestedFix
                )
            } else {
                merged.append(interval)
            }
        }

        // A long-form report should stay readable; retain the strongest 120 intervals.
        if merged.count > 120 {
            let severityOrder = ["低": 0, "中": 1, "高": 2]
            return Array(merged.sorted { a, b in
                let sa = (severityOrder[a.severity] ?? 0, a.confidence)
                let sb = (severityOrder[b.severity] ?? 0, b.confidence)
                if sa.0 != sb.0 { return sa.0 > sb.0 }
                return sa.1 > sb.1
            }.prefix(120)).sorted { $0.startTime < $1.startTime }
        }
        return merged
    }

    private static func spectralHoleScore(spectrum: [(frequency: Float, powerDb: Float)]) -> Float {
        let usable = spectrum.filter { $0.frequency >= 90 && $0.frequency < 12000 }
        guard usable.count > 12 else { return 0 }
        let stride = max(2, usable.count / 96)
        var bands: [Float] = []
        var index = 0
        while index < usable.count {
            let chunk = usable[index..<min(usable.count, index + stride)]
            let power = chunk.map { pow(10, $0.powerDb / 10) }.reduce(0, +)
            bands.append(DSP.db(sqrt(power / Float(max(1, chunk.count)))))
            index += stride
        }
        guard bands.count >= 5 else { return 0 }
        var holes = 0
        for i in bands.indices {
            let neighbors = bands.indices.filter { abs($0 - i) <= 2 && $0 != i }
            guard !neighbors.isEmpty else { continue }
            let sorted = neighbors.map { bands[$0] }.sorted()
            let median = sorted[sorted.count / 2]
            if bands[i] < median - 9 { holes += 1 }
        }
        return clamp01(Float(holes) / Float(bands.count) * 2.8)
    }

    private static func phaseInstabilityScore(channels: [[Float]]) -> Float {
        guard channels.count > 1, let count = channels.map(\.count).min(), count > 1024 else { return 0 }
        let segments = 16
        let length = max(1024, count / segments)
        var correlations: [Float] = []
        var start = 0
        while start + length <= count {
            if let correlation = DSP.correlation(Array(channels[0][start..<start+length]), Array(channels[1][start..<start+length])) {
                correlations.append(correlation)
            }
            start += length
        }
        guard correlations.count >= 3 else { return 0 }
        let mean = correlations.reduce(0, +) / Float(correlations.count)
        let variance = correlations.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Float(correlations.count)
        let deviation = sqrt(max(0, variance))
        let unstable = correlations.filter { $0 < 0.25 }.count
        return clamp01(deviation / 0.35) * 0.60 + clamp01(Float(unstable) / Float(correlations.count) / 0.45) * 0.40
    }

    private static func transientSmearScore(channels: [[Float]]) -> Float {
        guard let first = channels.first, first.count >= 4096 else { return 0 }
        let blockSize = 1024
        var envelopes: [Float] = []
        var start = 0
        while start + blockSize <= first.count {
            let block = Array(first[start..<start+blockSize])
            envelopes.append(DSP.rms(block))
            start += blockSize
        }
        guard envelopes.count >= 8 else { return 0 }
        let meanEnvelope = envelopes.reduce(0, +) / Float(envelopes.count)
        guard meanEnvelope > 1e-7 else { return 0 }
        var onsets: [Float] = []
        for i in 1..<envelopes.count {
            onsets.append(max(0, envelopes[i] - envelopes[i-1]))
        }
        let meanOnset = onsets.reduce(0, +) / Float(onsets.count)
        let attackRatio = meanOnset / meanEnvelope
        // Healthy musical envelopes usually show a moderate block-to-block rise. Very small
        // ratios often accompany over-smearing or heavy limiting.
        return clamp01((0.020 - attackRatio) / 0.018)
    }

    private static func normalize(value: Float, low: Float, high: Float) -> Float {
        clamp01((value - low) / (high - low))
    }

    private static func clamp01(_ value: Float) -> Float {
        max(0, min(1, value)) * 100
    }
}
