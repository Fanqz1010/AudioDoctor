import Accelerate
import Foundation

struct MusicKeyCandidate: Codable, Identifiable, Equatable {
    var id: String { name }
    let name: String
    let mode: String
    let score: Float
    let confidence: Float
}

struct MusicTonalityAnalysis: Codable, Equatable {
    let bestKeyName: String
    let tonicName: String
    let mode: String
    let confidence: Float
    let alternatives: [MusicKeyCandidate]
    let pitchClassEnergy: [Float]
    let interpretation: String
}

struct MusicTempoCandidate: Codable, Identifiable, Equatable {
    var id: String { String(format: "%.1f", bpm) }
    let bpm: Float
    let score: Float
}

struct MusicTempoAnalysis: Codable, Equatable {
    let bpm: Float
    let confidence: Float
    let beatIntervalSeconds: Float
    let estimatedBeats: Int
    let timeSignatureEstimate: String
    let timeSignatureConfidence: Float
    let onsetDensityPerMinute: Float
    let alternatives: [MusicTempoCandidate]
    let interpretation: String
}

struct MusicPartAnalysis: Codable, Identifiable, Equatable {
    var id: String { name }
    let name: String
    let role: String
    let confidence: Float
    let energyPercent: Float
    let evidence: String
}

struct MusicArrangementAnalysis: Codable, Equatable {
    let parts: [MusicPartAnalysis]
    let leadSummary: String
    let supportSummary: String
    let confidence: Float
    let interpretation: String
}

struct MusicStructureAnalysis: Codable, Equatable {
    let tonality: MusicTonalityAnalysis?
    let tempo: MusicTempoAnalysis?
    let arrangement: MusicArrangementAnalysis?
}

enum MusicStructureAnalyzer {
    private static let pitchNames = ["C", "C♯/D♭", "D", "D♯/E♭", "E", "F", "F♯/G♭", "G", "G♯/A♭", "A", "A♯/B♭", "B"]
    private static let majorProfile: [Float] = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    private static let minorProfile: [Float] = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

    static func analyze(channels: [[Float]], sampleRate: Float, stereoCorrelation: Float?, stereoWidthPercent: Float?) -> MusicStructureAnalysis? {
        guard sampleRate > 0, let first = channels.first, first.count >= 8192 else { return nil }

        let mono = mixdown(channels)
        let frames = spectralFrames(mono, sampleRate: sampleRate)
        guard !frames.isEmpty else { return nil }

        let chroma = chromaVector(frames: frames, sampleRate: sampleRate)
        let tonality = chroma.isEmpty ? nil : tonality(chroma: chroma)
        let flux = onsetFlux(frames: frames)
        let tempo = tempo(flux: flux, sampleRate: sampleRate, frameCount: mono.count)
        let arrangement = arrangement(
            frames: frames,
            sampleRate: sampleRate,
            flux: flux,
            chroma: chroma,
            sourceSampleCount: mono.count,
            stereoCorrelation: stereoCorrelation,
            stereoWidthPercent: stereoWidthPercent
        )
        return MusicStructureAnalysis(tonality: tonality, tempo: tempo, arrangement: arrangement)
    }

    // MARK: - Signal preparation

    private static func mixdown(_ channels: [[Float]]) -> [Float] {
        guard let first = channels.first else { return [] }
        guard channels.count > 1, let second = channels.dropFirst().first else { return first }
        let count = min(first.count, second.count)
        var output = [Float](repeating: 0, count: count)
        for i in 0..<count { output[i] = (first[i] + second[i]) * 0.5 }
        return output
    }

    private static func spectralFrames(_ input: [Float], sampleRate: Float, fftSize: Int = 4096, maxFrames: Int = 180) -> [[Float]] {
        let hop = fftSize / 2
        guard input.count >= fftSize else { return [] }
        let availableFrames = (input.count - fftSize) / hop + 1
        let stride = max(1, availableFrames / maxFrames)
        var frames: [[Float]] = []
        var start = 0
        let window = DSP.hannWindow(fftSize)
        while start + fftSize <= input.count && frames.count < maxFrames {
            var frame = Array(input[start..<(start + fftSize)])
            let mean = frame.reduce(0, +) / Float(frame.count)
            for i in frame.indices { frame[i] -= mean }
            for i in frame.indices { frame[i] *= window[i] }
            let spectrum = DSP.realFFTMagnitudes(frame)
            if !spectrum.isEmpty { frames.append(spectrum) }
            start += hop * stride
        }
        return frames
    }

    // MARK: - Tonality

    private static func chromaVector(frames: [[Float]], sampleRate: Float) -> [Float] {
        var chroma = [Float](repeating: 0, count: 12)
        let binHz = sampleRate / Float(frames[0].count)
        let lowBin = max(1, Int(55 / binHz))
        let highBin = min(frames[0].count - 1, Int(2200 / binHz))
        guard lowBin < highBin else { return [] }

        for spectrum in frames {
            var frameChroma = [Float](repeating: 0, count: 12)
            var framePower: Float = 0
            for bin in lowBin...highBin {
                let frequency = Float(bin) * binHz
                let midi = 69.0 + 12.0 * log2(Double(frequency / 440.0))
                let midiNumber = Int(midi.rounded())
                guard midiNumber >= 33 && midiNumber <= 104 else { continue }
                let compressed = log1p(Float(spectrum[bin]) * 100)
                let pitchClass = ((midiNumber % 12) + 12) % 12
                // Slight harmonic de-emphasis: higher octaves contribute less than fundamentals.
                let octaveWeight = Float(max(0.45, 1.0 - Double(midiNumber - 33) / 110.0))
                frameChroma[pitchClass] += compressed * octaveWeight
                framePower += compressed
            }
            guard framePower > 0 else { continue }
            for i in chroma.indices { chroma[i] += frameChroma[i] / framePower }
        }

        let sum = chroma.reduce(0, +)
        guard sum > 0 else { return [] }
        for i in chroma.indices { chroma[i] /= sum }
        return chroma
    }

    private static func tonality(chroma: [Float]) -> MusicTonalityAnalysis {
        var candidates: [MusicKeyCandidate] = []
        for rotation in 0..<12 {
            let rotated = rotate(chroma, offset: rotation)
            let majorScore = pearson(rotated, majorProfile)
            let minorScore = pearson(rotated, minorProfile)
            let majorConfidence = confidence(fromScore: majorScore)
            let minorConfidence = confidence(fromScore: minorScore)
            candidates.append(MusicKeyCandidate(
                name: "\(pitchNames[rotation]) 大调",
                mode: "大调",
                score: majorScore,
                confidence: majorConfidence
            ))
            candidates.append(MusicKeyCandidate(
                name: "\(pitchNames[rotation]) 小调",
                mode: "小调",
                score: minorScore,
                confidence: minorConfidence
            ))
        }
        candidates.sort { $0.score > $1.score }
        let best = candidates[0]
        let secondScore = candidates.count > 1 ? candidates[1].score : 0
        let margin = max(0, best.score - secondScore)
        let combined = min(0.96, max(0.15, best.score * 0.68 + margin * 1.8))
        let alternatives = Array(candidates.dropFirst().prefix(3))
        let tonicName = pitchNames.first { best.name.hasPrefix($0) } ?? String(best.name.prefix(1))
        let topEnergy = chroma.max() ?? 0
        let averageEnergy = chroma.reduce(0, +) / Float(max(1, chroma.count))
        let clarity = topEnergy / max(averageEnergy, 1e-6)
        let interpretation = clarity > 1.7
            ? "调性中心比较清楚，但自动判断仍可能把关系大小调或同主音大小调混淆。"
            : "音高分布较分散，调性判断置信度较低，建议结合人耳确认主音和结束音。"
        return MusicTonalityAnalysis(
            bestKeyName: best.name,
            tonicName: tonicName,
            mode: best.mode,
            confidence: combined,
            alternatives: alternatives,
            pitchClassEnergy: chroma,
            interpretation: interpretation
        )
    }

    private static func confidence(fromScore score: Float) -> Float {
        min(1, max(0, (score + 0.15) / 1.15))
    }

    private static func rotate(_ values: [Float], offset: Int) -> [Float] {
        guard values.count == 12 else { return values }
        return (0..<12).map { values[($0 + offset) % 12] }
    }

    private static func pearson(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, a.count > 1 else { return 0 }
        let meanA = a.reduce(0, +) / Float(a.count)
        let meanB = b.reduce(0, +) / Float(b.count)
        var numerator: Float = 0
        var deltaA: Float = 0
        var deltaB: Float = 0
        for i in a.indices {
            let x = a[i] - meanA
            let y = b[i] - meanB
            numerator += x * y
            deltaA += x * x
            deltaB += y * y
        }
        let denominator = sqrt(max(deltaA * deltaB, 0))
        return denominator > 0 ? numerator / denominator : 0
    }

    // MARK: - Tempo and meter

    private static func onsetFlux(frames: [[Float]]) -> [Float] {
        guard frames.count > 1 else { return [] }
        var flux: [Float] = []
        for index in 1..<frames.count {
            let previous = frames[index - 1]
            let current = frames[index]
            var positiveSum: Float = 0
            let minimumBins = min(previous.count, current.count)
            for bin in 0..<minimumBins { positiveSum += max(0, current[bin] - previous[bin]) }
            flux.append(positiveSum)
        }
        return flux
    }

    private static func tempo(flux: [Float], sampleRate: Float, frameCount: Int) -> MusicTempoAnalysis? {
        guard flux.count >= 16 else { return nil }
        let fftSize = 4096
        let hop = fftSize / 2
        let stride = max(1, ((frameCount - fftSize) / hop + 1) / flux.count)
        let framesPerSecond = sampleRate / Float(hop * stride)
        let mean = flux.reduce(0, +) / Float(flux.count)
        let centered = flux.map { $0 - mean }
        let centeredEnergy = centered.map { $0 * $0 }.reduce(0, +)
        guard centeredEnergy > 0 else { return nil }

        var rawCandidates: [MusicTempoCandidate] = []
        let minimumLag = max(2, Int((framesPerSecond * 60.0 / 220.0).rounded()))
        let maximumLag = min(centered.count - 2, Int((framesPerSecond * 60.0 / 45.0).rounded()))
        guard minimumLag < maximumLag else { return nil }

        for lag in minimumLag...maximumLag {
            var score: Float = 0
            var energyA: Float = 0
            var energyB: Float = 0
            for index in 0..<(centered.count - lag) {
                let a = centered[index]
                let b = centered[index + lag]
                score += a * b
                energyA += a * a
                energyB += b * b
            }
            let denominator = sqrt(max(energyA * energyB, 0))
            guard denominator > 0 else { continue }
            let normalized = score / denominator
            let bpm = framesPerSecond * 60.0 / Float(lag)
            // Popular music is commonly between 80 and 160 BPM. Keep this prior gentle.
            let prior: Float = 0.72 + 0.28 * exp(-pow((bpm - 125) / 55, 2))
            rawCandidates.append(MusicTempoCandidate(bpm: bpm, score: normalized * prior))
        }

        var peaks = rawCandidates.filter { candidate in
            let bpm = candidate.bpm
            return !rawCandidates.contains { other in
                abs(other.bpm - bpm) < 1.5 && other.score > candidate.score
            }
        }
        peaks.sort { $0.score > $1.score }
        guard var best = peaks.first else { return nil }

        // FFT-frame lags are integer-only. A parabolic interpolation around the
        // winning lag recovers sub-frame timing and typically improves 120 BPM tests
        // from roughly 117 BPM to much closer to the intended tempo.
        if let nearestIndex = rawCandidates.indices.first(where: { abs(rawCandidates[$0].bpm - best.bpm) < 0.01 }),
           nearestIndex > 0, nearestIndex + 1 < rawCandidates.count {
            let previousScore = rawCandidates[nearestIndex - 1].score
            let currentScore = rawCandidates[nearestIndex].score
            let nextScore = rawCandidates[nearestIndex + 1].score
            let denominator = previousScore - 2 * currentScore + nextScore
            if abs(denominator) > 1e-7 {
                let delta = max(-0.5, min(0.5, 0.5 * (previousScore - nextScore) / denominator))
                let originalLag = framesPerSecond * 60.0 / best.bpm
                let refinedLag = max(2.0, originalLag + delta)
                let refinedBPM = framesPerSecond * 60.0 / refinedLag
                best = MusicTempoCandidate(bpm: refinedBPM, score: currentScore)
            }
        }

        // Resolve obvious half/double-time aliases into a practical 70–180 BPM range.
        while best.bpm < 70 { best = MusicTempoCandidate(bpm: best.bpm * 2, score: best.score) }
        while best.bpm > 185 { best = MusicTempoCandidate(bpm: best.bpm / 2, score: best.score) }

        let scores = peaks.map(\.score)
        let averageScore = scores.reduce(0, +) / Float(max(1, scores.count))
        let secondScore = peaks.count > 1 ? peaks[1].score : averageScore
        let contrast = best.score / max(averageScore, 1e-6)
        let margin = max(0, best.score - secondScore)
        let confidence = min(0.96, max(0.12, 0.28 * contrast + 3.2 * margin + 0.18))

        let beatInterval: Float = 60.0 / best.bpm
        let duration = Float(frameCount) / sampleRate
        let beats = Int((duration / beatInterval).rounded())
        let fourBar = normalizedAutocorrelation(centered, lag: Int((framesPerSecond * beatInterval * 4).rounded()))
        let threeBar = normalizedAutocorrelation(centered, lag: Int((framesPerSecond * beatInterval * 3).rounded()))
        let meterDifference = abs(fourBar - threeBar)
        let meter: String
        if meterDifference < 0.35 {
            meter = "拍号待确认（常见 4/4）"
        } else if fourBar > threeBar {
            meter = "4/4（推测）"
        } else {
            meter = "3/4（推测）"
        }
        let meterConfidence = min(0.9, max(0.15, 0.25 + meterDifference * 1.8))

        let threshold = mean + 1.1 * standardDeviation(flux)
        let onsets = flux.filter { $0 > threshold }.count
        let onsetDensity = Float(onsets) / duration * 60
        let alternatives = Array(peaks.prefix(3))
        let interpretation = confidence > 0.65
            ? "节拍周期较明显，适合作为粗略 BPM 参考。"
            : "节拍线索较弱，可能是散板、慢歌或编曲 transient 不明显，建议人工打拍确认。"

        return MusicTempoAnalysis(
            bpm: best.bpm,
            confidence: confidence,
            beatIntervalSeconds: beatInterval,
            estimatedBeats: beats,
            timeSignatureEstimate: meter,
            timeSignatureConfidence: meterConfidence,
            onsetDensityPerMinute: onsetDensity,
            alternatives: alternatives,
            interpretation: interpretation
        )
    }

    private static func normalizedAutocorrelation(_ values: [Float], lag: Int) -> Float {
        guard lag > 1, lag < values.count - 1 else { return 0 }
        var score: Float = 0
        var energyA: Float = 0
        var energyB: Float = 0
        for index in 0..<(values.count - lag) {
            let a = values[index]
            let b = values[index + lag]
            score += a * b
            energyA += a * a
            energyB += b * b
        }
        let denominator = sqrt(max(energyA * energyB, 0))
        return denominator > 0 ? score / denominator : 0
    }

    private static func standardDeviation(_ values: [Float]) -> Float {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Float(values.count)
        let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Float(values.count - 1)
        return sqrt(max(0, variance))
    }

    // MARK: - Arrangement role estimation

    private static func arrangement(
        frames: [[Float]],
        sampleRate: Float,
        flux: [Float],
        chroma: [Float],
        sourceSampleCount: Int,
        stereoCorrelation: Float?,
        stereoWidthPercent: Float?
    ) -> MusicArrangementAnalysis {
        let features = spectralFeatures(frames: frames, sampleRate: sampleRate, flux: flux, chroma: chroma)
        let onsetDensity = features.onsetDensity
        let leadVocal = features.vocalBand * 0.45 + features.midBand * 0.25 + features.sustain * 0.2 + features.pitchClarity * 0.1
        let leadInstrument = features.midBand * 0.38 + features.pitchClarity * 0.27 + features.sustain * 0.2 + features.highBand * 0.15
        let bass = features.bassBand * 0.78 + features.lowTransient * 0.12 + features.sustain * 0.10
        let drums = features.transientDensity * 0.52 + features.broadbandTransient * 0.28 + features.highBand * 0.10 + features.bassBand * 0.10
        let pad = features.sustain * 0.48 + features.highBand * 0.22 + max(0, (stereoWidthPercent ?? 0) / 100) * 0.18 + features.midBand * 0.12
        let harmonicAccompaniment = features.midBand * 0.38 + features.transientDensity * 0.27 + features.pitchClarity * 0.2 + features.highBand * 0.15

        var parts: [MusicPartAnalysis] = []
        func appendPart(_ name: String, role: String, strength: Float, energyPercent: Float, evidence: String) {
            let confidence = min(0.9, max(0.1, strength * 0.82 + features.signalConfidence * 0.18))
            parts.append(MusicPartAnalysis(
                name: name,
                role: role,
                confidence: confidence,
                energyPercent: energyPercent,
                evidence: evidence
            ))
        }

        appendPart(
            "人声 / 主旋律",
            role: strengthToRole(leadVocal),
            strength: leadVocal,
            energyPercent: features.vocalBand * 100,
            evidence: "250–900Hz 与 2–5kHz 能量、持续音高线索"
        )
        appendPart(
            "主奏乐器 / 合成 Lead",
            role: strengthToRole(leadInstrument),
            strength: leadInstrument,
            energyPercent: features.midBand * 100,
            evidence: "中频旋律能量、音高集中度与持续度"
        )
        appendPart(
            "低音 / Bass",
            role: "低频支撑",
            strength: bass,
            energyPercent: features.bassBand * 100,
            evidence: "30–180Hz 能量及低频瞬态"
        )
        appendPart(
            "鼓组 / 打击乐",
            role: onsetDensity > 60 ? "节奏基础" : "节奏辅助",
            strength: drums,
            energyPercent: features.broadbandTransient * 100,
            evidence: String(format: "Onset 密度 %.0f/分钟，宽带瞬态 %.0f%%", onsetDensity, features.broadbandTransient * 100)
        )
        appendPart(
            "和声垫 / Pad",
            role: "氛围辅助",
            strength: pad,
            energyPercent: features.sustain * 100,
            evidence: String(format: "持续度 %.0f%%，立体声宽度 %.0f%%", features.sustain * 100, stereoWidthPercent ?? 0)
        )
        appendPart(
            "吉他 / 键盘类和声",
            role: "和声辅助",
            strength: harmonicAccompaniment,
            energyPercent: features.midBand * 100,
            evidence: "中频谐波、音高集中度与中等瞬态"
        )

        parts.sort { $0.confidence > $1.confidence }
        // A drum or bass layer can dominate energy, but it is not usually the
        // musical "lead" requested by annotators. Keep them as rhythm/support roles.
        let melodicParts = parts.filter { $0.name != "鼓组 / 打击乐" && $0.name != "低音 / Bass" }
        let strongestMelodic = melodicParts.first ?? parts.first
        var lead = strongestMelodic?.name ?? "无法判断"
        if let strongestMelodic {
            lead += "（\(Int(strongestMelodic.confidence * 100))% 置信度）"
        }
        let supportItems = parts
            .filter { $0.name != strongestMelodic?.name }
            .prefix(3)
        let support = supportItems
            .map { "\($0.name)：\($0.role)" }
            .joined(separator: "；")
        let averageConfidence = parts.map(\.confidence).reduce(0, +) / Float(max(1, parts.count))
        return MusicArrangementAnalysis(
            parts: parts,
            leadSummary: lead,
            supportSummary: support.isEmpty ? "未形成稳定辅助层判断" : support,
            confidence: min(0.9, max(0.1, averageConfidence)),
            interpretation: "这是混合音频中的频谱/瞬态/立体声角色推测，不是源分离结果，不能保证精确识别真实乐器。"
        )
    }

    private static func strengthToRole(_ strength: Float) -> String {
        if strength > 0.52 { return "疑似主奏" }
        if strength > 0.34 { return "重要辅助" }
        return "辅助/背景"
    }

    private static func spectralFeatures(frames: [[Float]], sampleRate: Float, flux: [Float], chroma: [Float]) -> (
        bassBand: Float,
        lowTransient: Float,
        midBand: Float,
        vocalBand: Float,
        highBand: Float,
        sustain: Float,
        transientDensity: Float,
        broadbandTransient: Float,
        pitchClarity: Float,
        onsetDensity: Float,
        signalConfidence: Float
    ) {
        guard let first = frames.first, !first.isEmpty else {
            return (0,0,0,0,0,0,0,0,0,0,0)
        }
        let binHz = sampleRate / Float(first.count)
        var bands = [Float](repeating: 0, count: 8)
        var frameEnergies: [Float] = []
        for spectrum in frames {
            var total: Float = 0
            var bandTotals = [Float](repeating: 0, count: 8)
            for bin in 1..<spectrum.count {
                let frequency = Float(bin) * binHz
                let value = log1p(spectrum[bin] * 100)
                total += value
                let bandIndex: Int
                switch frequency {
                case ..<30: continue
                case ..<180: bandIndex = 0
                case ..<250: bandIndex = 1
                case ..<900: bandIndex = 2
                case ..<2000: bandIndex = 3
                case ..<5000: bandIndex = 4
                case ..<8000: bandIndex = 5
                case ..<12000: bandIndex = 6
                default: bandIndex = 7
                }
                bandTotals[bandIndex] += value
            }
            guard total > 0 else { continue }
            for i in bands.indices { bands[i] += bandTotals[i] / total }
            frameEnergies.append(total)
        }
        let frameCount = Float(max(1, frames.count))
        let frameCount0 = frames.reduce(0) { $0 + $1.count }
        for i in bands.indices { bands[i] /= frameCount }

        // Normalize relative to a typical spectral distribution; these are heuristic roles.
        func normalize(_ value: Float, center: Float, span: Float) -> Float {
            min(1, max(0, (value - center + span * 0.5) / span))
        }
        let bass = normalize(bands[0] + bands[1] * 0.4, center: 0.09, span: 0.18)
        let lowTransient = min(1, bass * 1.1)
        let mid = normalize(bands[2] + bands[3] * 0.8, center: 0.32, span: 0.34)
        let vocal = normalize(bands[2] * 0.65 + bands[4] * 0.45, center: 0.30, span: 0.38)
        let high = normalize(bands[4] * 0.45 + bands[5] * 0.30 + bands[6] * 0.15, center: 0.24, span: 0.32)

        let energyMean = frameEnergies.reduce(0, +) / frameCount
        let activeFrames = frameEnergies.filter { $0 > energyMean * 0.35 }.count
        let sustain = min(1, Float(activeFrames) / frameCount)

        let fluxMean = flux.reduce(0, +) / Float(max(1, flux.count))
        let fluxStd = standardDeviation(flux)
        let peaks = flux.filter { $0 > fluxMean + fluxStd }.count
        let durationSeconds = Float(frameCount0) / sampleRate
        let onsetDensity = durationSeconds > 0 ? Float(peaks) / durationSeconds * 60 : 0
        let transientDensity = min(1, onsetDensity / 220)
        let broadbandTransient = min(1, fluxStd / max(fluxMean, 1e-6) / 2.2)

        let chromaMean = chroma.count == 12
            ? chroma.reduce(0, +) / Float(chroma.count)
            : 0
        let chromaPeak = chroma.max() ?? 0
        let pitchClarity = chromaMean > 0
            ? min(1, max(0, (chromaPeak / chromaMean - 1.0) / 3.0))
            : 0

        let maximumEnergy = frameEnergies.max() ?? 0
        let signalConfidence = min(1, maximumEnergy > 0 ? energyMean / maximumEnergy * 2.0 : 0)
        return (
            bass,
            lowTransient,
            mid,
            vocal,
            high,
            sustain,
            transientDensity,
            broadbandTransient,
            pitchClarity,
            onsetDensity,
            signalConfidence
        )
    }
}
