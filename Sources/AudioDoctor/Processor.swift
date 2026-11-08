import Accelerate
import Foundation

enum ContentPreset: String, CaseIterable, Identifiable, Codable {
    case general
    case sunoVocal = "suno-vocal"
    case sunoPop = "suno-pop"
    case electronic
    case cinematic
    case podcast

    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: return "通用音乐"
        case .sunoVocal: return "Suno 人声"
        case .sunoPop: return "Suno 流行"
        case .electronic: return "电子 / 舞曲"
        case .cinematic: return "影视 / 配乐"
        case .podcast: return "播客 / 口播"
        }
    }

    var summary: String {
        switch self {
        case .general: return "保守修复薄、沙、糊，适合没有明确风格参考的音频。"
        case .sunoVocal: return "压少一些高频闪烁，保留人声清晰度和轻微空气感。"
        case .sunoPop: return "补低频身体感和鼓组瞬态，让生成音乐更像成品流行曲。"
        case .electronic: return "强化低频稳定度与节奏攻击力，避免高频金属感。"
        case .cinematic: return "保持宽空间，低频更干净，瞬态不做过度强调。"
        case .podcast: return "以可懂度和相位兼容为主，处理沙声与近讲单薄感。"
        }
    }

    var lowGain: Float {
        switch self {
        case .general: return 2.0
        case .sunoVocal: return 1.2
        case .sunoPop: return 2.0
        case .electronic: return 1.8
        case .cinematic: return 1.4
        case .podcast: return 0.7
        }
    }

    var midGain: Float {
        switch self {
        case .general: return 0.5
        case .sunoVocal: return 0.8
        case .sunoPop: return 0.6
        case .electronic: return 0.3
        case .cinematic: return 0.4
        case .podcast: return 0.8
        }
    }

    var highMidGain: Float {
        switch self {
        case .general: return -0.4
        case .sunoVocal: return 0.5
        case .sunoPop: return 0.2
        case .electronic: return -0.2
        case .cinematic: return -0.3
        case .podcast: return 0.5
        }
    }

    var airGain: Float {
        switch self {
        case .general: return 1.3
        case .sunoVocal: return 1.1
        case .sunoPop: return 1.5
        case .electronic: return 1.0
        case .cinematic: return 0.8
        case .podcast: return 0.5
        }
    }

    var transientAmount: Float {
        switch self {
        case .general: return 0.55
        case .sunoVocal: return 0.45
        case .sunoPop: return 0.75
        case .electronic: return 0.80
        case .cinematic: return 0.45
        case .podcast: return 0.25
        }
    }

    var lowMonoAmount: Float {
        switch self {
        case .general: return 0.32
        case .sunoVocal: return 0.42
        case .sunoPop: return 0.40
        case .electronic: return 0.58
        case .cinematic: return 0.25
        case .podcast: return 0.70
        }
    }

    var deHissCutoff: Float { 7000 + Float(600) }
    var deHissAmount: Float {
        switch self {
        case .general: return 1.0
        case .sunoVocal: return 1.08
        case .sunoPop: return 0.95
        case .electronic: return 0.90
        case .cinematic: return 0.82
        case .podcast: return 1.15
        }
    }
}

struct RepairOptions: Codable {
    var deHiss = true
    var fullness = true
    var matchReference = true
    var exciter = true
    var transientRecovery = true
    var lowFrequencyMono = true
    var loudnessNormalize = true
    var targetLUFS: Float = -14
    var strength: Float = 1.0
    var presetRawValue = ContentPreset.general.rawValue

    var preset: ContentPreset {
        ContentPreset(rawValue: presetRawValue) ?? .general
    }
}

enum AudioProcessor {
    static func convert(channels: [[Float]], sampleRate: Float, target: String) throws -> [[Float]] {
        switch target {
        case "mono":
            guard channels.count > 1 else { return channels }
            let count = channels[0].count
            var mono = [Float](repeating: 0, count: count)
            for i in 0..<count { mono[i] = (channels[0][i] + channels[1][i]) * 0.5 }
            return [mono]
        case "stereo":
            if channels.count == 1 {
                return [channels[0], channels[0]]
            }
            return [channels[0], channels.count > 1 ? channels[1] : channels[0]]
        case "surround51":
            return try upmixToSurround51(channels: channels, sampleRate: sampleRate)
        case "ambix":
            return try upmixToFirstOrderAmbix(channels: channels)
        default:
            return channels
        }
    }

    static func repair(channels: [[Float]], sampleRate: Float, options: RepairOptions, referenceChannels: [[Float]]? = nil) -> [[Float]] {
        var output = channels
        let strength = max(0, min(1.5, options.strength))
        let preset = options.preset

        // 1. Reduce stationary high-band artifacts before adding brightness.
        if options.deHiss {
            output = deHiss(output, sampleRate: sampleRate, strength: strength, preset: preset)
        }

        // 2. Restore tonal balance. A user reference wins over a generic preset,
        //    but both remain limited to conservative corrections.
        if options.fullness {
            if let referenceChannels, options.matchReference {
                output = matchReferenceBands(output, reference: referenceChannels, sampleRate: sampleRate, strength: strength)
            } else {
                output = addFullness(output, sampleRate: sampleRate, strength: strength, preset: preset)
            }
        }

        // 3. Improve mono compatibility before widening/detail enhancement.
        if options.lowFrequencyMono, output.count > 1 {
            output = stabilizeLowFrequency(output, sampleRate: sampleRate, strength: strength, preset: preset)
        }

        // 4. Recover attacks without changing overall level as much as a compressor.
        if options.transientRecovery {
            output = recoverTransients(output, sampleRate: sampleRate, strength: strength, preset: preset)
        }

        if options.exciter {
            // Do not re-amplify a still-noisy high band. This avoids the common
            // one-click failure mode where de-hiss is followed by an exciter.
            let repairedSpectrum = DSP.averageSpectrum(channels: output, sampleRate: sampleRate, maxFrames: 120)
            var airStrength = strength
            if !repairedSpectrum.isEmpty {
                let totalPower: Float = repairedSpectrum.map { pow(10, $0.powerDb / 10) }.reduce(0, +)
                let highPower: Float = repairedSpectrum.filter { $0.frequency >= 9000 }
                    .map { pow(10, $0.powerDb / 10) }
                    .reduce(0, +)
                if totalPower > 0 {
                    let highRatio = DSP.db(sqrt(highPower / totalPower))
                    if highRatio > -14 { airStrength = min(airStrength, strength * 0.18) }
                }
            }
            output = addAirAndDetail(output, sampleRate: sampleRate, strength: airStrength, preset: preset)
        }

        if options.loudnessNormalize, let lufs = DSP.kWeightedLUFS(channels: output, sampleRate: sampleRate) {
            let gainDb = options.targetLUFS - lufs
            DSP.applyGain(&output, gain: pow(10, gainDb / 20))
        }
        DSP.limit(&output, sampleRate: sampleRate, ceiling: pow(10, -1 / 20))
        return output
    }

    /// Normalize an arbitrary input to a working stereo pair. Spatial conversion is
    /// intentionally based on the left/right pair; mono is duplicated and files with
    /// more than two channels use their first two channels.
    private static func workingStereo(channels: [[Float]]) throws -> [[Float]] {
        guard let first = channels.first, !first.isEmpty else {
            throw NSError(domain: "AudioDoctor", code: 10, userInfo: [NSLocalizedDescriptionKey: "没有可用于空间转换的音频数据"])
        }
        guard channels.count > 1, let second = channels.dropFirst().first, !second.isEmpty else {
            return [first, first]
        }
        let count = min(first.count, second.count)
        return [Array(first.prefix(count)), Array(second.prefix(count))]
    }

    /// Conservative stereo-to-5.1 upmix. Channel order is WAV/ITU style:
    /// L, R, C, LFE, Ls, Rs. The front pair remains closest to the source,
    /// center/LFE come from mid, and surrounds come from band-limited side.
    private static func upmixToSurround51(channels: [[Float]], sampleRate: Float) throws -> [[Float]] {
        let stereo = try workingStereo(channels: channels)
        let left = stereo[0]
        let right = stereo[1]
        let count = left.count
        let mid = (0..<count).map { (left[$0] + right[$0]) * 0.5 }
        let side = (0..<count).map { (left[$0] - right[$0]) * 0.5 }

        let centerLow = Biquad(BiquadCoefficients.lowPass(sampleRate: sampleRate, frequency: 11000, q: 0.6))
        let centerHigh = Biquad(BiquadCoefficients.highPass(sampleRate: sampleRate, frequency: 90, q: 0.6))
        var center = centerLow.process(mid)
        centerHigh.processInPlace(&center)

        let lfeFilter1 = Biquad(BiquadCoefficients.lowPass(sampleRate: sampleRate, frequency: 120, q: 0.6))
        let lfeFilter2 = Biquad(BiquadCoefficients.lowPass(sampleRate: sampleRate, frequency: 120, q: 0.6))
        var lfe = lfeFilter1.process(mid)
        lfeFilter2.processInPlace(&lfe)

        let surroundLow = Biquad(BiquadCoefficients.lowPass(sampleRate: sampleRate, frequency: 7500, q: 0.6))
        let surroundHigh = Biquad(BiquadCoefficients.highPass(sampleRate: sampleRate, frequency: 250, q: 0.6))
        // Near-mono material has no side information. Add a small delayed mid
        // component then, so 5.1 export does not produce two completely silent
        // surround channels; true stereo width still comes from side first.
        let sideRatio = DSP.rms(side) / max(DSP.rms(mid), 1e-9)
        let monoFill = max(0, min(1, 0.20 * (1 - sideRatio)))
        let surroundSource = (0..<count).map { side[$0] + mid[$0] * monoFill }
        var surroundAmbience = surroundLow.process(surroundSource)
        surroundHigh.processInPlace(&surroundAmbience)

        var output: [[Float]] = []
        output.reserveCapacity(6)
        output.append(left.map { $0 * 0.92 })
        output.append(right.map { $0 * 0.92 })
        output.append(center.map { $0 * 0.58 })
        output.append(lfe.map { $0 * 0.82 })
        output.append(delay(surroundAmbience, sampleRate: sampleRate, seconds: 0.020).map { $0 * 0.42 })
        output.append(delay(surroundAmbience, sampleRate: sampleRate, seconds: 0.026).map { $0 * -0.38 })
        DSP.limit(&output, sampleRate: sampleRate, ceiling: pow(10, -1 / 20))
        return output
    }

    /// First-order AmbiX approximation using ACN/SN3D channel order: W, Y, Z, X.
    /// Left/right are treated as virtual sources at ±30°. Z is zero because a
    /// normal stereo file has no elevation information.
    private static func upmixToFirstOrderAmbix(channels: [[Float]]) throws -> [[Float]] {
        let stereo = try workingStereo(channels: channels)
        let left = stereo[0]
        let right = stereo[1]
        let count = left.count
        // A 0.55 safety attenuation keeps common masters below the limiter while
        // preserving the W/X/Y proportions of a first-order encoding.
        let attenuation: Float = 0.55
        var w = [Float](repeating: 0, count: count)
        var y = [Float](repeating: 0, count: count)
        let z = [Float](repeating: 0, count: count)
        var x = [Float](repeating: 0, count: count)
        let wGain: Float = 0.70710678118 * attenuation
        let yGain: Float = 0.5 * attenuation
        let xGain: Float = 0.86602540378 * attenuation
        for i in 0..<count {
            w[i] = (left[i] + right[i]) * wGain
            y[i] = (left[i] - right[i]) * yGain
            x[i] = (left[i] + right[i]) * xGain
        }
        var output = [w, y, z, x]
        normalizePeak(&output, ceiling: pow(10, -1 / 20))
        return output
    }

    private static func delay(_ input: [Float], sampleRate: Float, seconds: Float) -> [Float] {
        let offset = max(0, Int((seconds * sampleRate).rounded()))
        var output = [Float](repeating: 0, count: input.count)
        guard offset < input.count else { return output }
        for i in offset..<input.count {
            output[i] = input[i - offset]
        }
        return output
    }

    private static func normalizePeak(_ channels: inout [[Float]], ceiling: Float) {
        var peak: Float = 0
        for channel in channels {
            for sample in channel { peak = max(peak, abs(sample)) }
        }
        guard peak > ceiling else { return }
        let gain = ceiling / peak
        for c in channels.indices {
            for i in channels[c].indices {
                channels[c][i] *= gain
            }
        }
    }

    private static func deHiss(_ channels: [[Float]], sampleRate: Float, strength: Float, preset: ContentPreset) -> [[Float]] {
        let cutoff = min(preset.deHissCutoff, sampleRate / 2 - 100)
        guard cutoff > 100 else { return channels }
        let high = Biquad(BiquadCoefficients.highPass(sampleRate: sampleRate, frequency: cutoff, q: 0.6))
        let low = Biquad(BiquadCoefficients.lowPass(sampleRate: sampleRate, frequency: cutoff, q: 0.6))
        var output: [[Float]] = []
        for channel in channels {
            let lowBand = low.process(channel)
            var highBand = high.process(channel)
            var envelope = [Float](repeating: 0, count: highBand.count)
            let attack: Float = 0.004
            let release: Float = 0.080
            let a = exp(-1 / (sampleRate * attack))
            let r = exp(-1 / (sampleRate * release))
            var env: Float = 0
            for i in 0..<highBand.count {
                env = abs(highBand[i]) > env ? abs(highBand[i]) : env * r + abs(highBand[i]) * (1 - r)
                envelope[i] = env
            }
            var smoothed = envelope
            for i in 1..<smoothed.count { smoothed[i] = a * smoothed[i-1] + (1-a) * smoothed[i] }
            let sortedEnvelope = smoothed.sorted()
            let threshold = sortedEnvelope[Int(Double(sortedEnvelope.count) * 0.45)] * 1.6
            var reductionDb = -7.0 * strength * preset.deHissAmount
            for i in 0..<highBand.count {
                let ratio = smoothed[i] / max(threshold, 1e-8)
                let attenuation = ratio < 1 ? max(reductionDb, reductionDb * ratio) : 0
                highBand[i] *= pow(10, attenuation / 20)
            }
            reductionDb = 0
            var mixed = [Float](repeating: 0, count: channel.count)
            for i in 0..<mixed.count { mixed[i] = lowBand[i] + highBand[i] }
            output.append(mixed)
        }
        return output
    }

    private static func addFullness(_ channels: [[Float]], sampleRate: Float, strength: Float, preset: ContentPreset) -> [[Float]] {
        let eqs: [(Float, Float, Float, Float)] = [
            (55, preset.lowGain, 0.7, 1),
            (105, preset.lowGain * 0.65, 0.7, 1),
            (260, preset.midGain, 0.8, 1),
            (3200, preset.highMidGain, 1.0, 1)
        ]
        var output: [[Float]] = []
        for channel in channels {
            var y = channel
            for (frequency, gain, q, _) in eqs {
                let shelf: Biquad
                if frequency <= 120 { shelf = Biquad(BiquadCoefficients.lowShelf(sampleRate: sampleRate, frequency: frequency, gain: gain * strength, q: q)) }
                else { shelf = Biquad(BiquadCoefficients.peaking(sampleRate: sampleRate, frequency: frequency, gain: gain * strength, q: q)) }
                y = shelf.process(y)
            }
            output.append(y)
        }
        return output
    }

    /// Keep the low end phase-coherent. This directly reduces mono fold-down cancellation
    /// and the unstable bass image common in generated stereo mixes.
    private static func stabilizeLowFrequency(_ channels: [[Float]], sampleRate: Float, strength: Float, preset: ContentPreset) -> [[Float]] {
        guard channels.count > 1 else { return channels }
        let cutoff: Float = 125
        let amount = max(0, min(0.85, preset.lowMonoAmount * min(1.2, strength)))
        let leftLowFilter = Biquad(BiquadCoefficients.lowPass(sampleRate: sampleRate, frequency: cutoff, q: 0.62))
        let rightLowFilter = Biquad(BiquadCoefficients.lowPass(sampleRate: sampleRate, frequency: cutoff, q: 0.62))
        let leftHighFilter = Biquad(BiquadCoefficients.highPass(sampleRate: sampleRate, frequency: cutoff, q: 0.62))
        let rightHighFilter = Biquad(BiquadCoefficients.highPass(sampleRate: sampleRate, frequency: cutoff, q: 0.62))
        let count = min(channels[0].count, channels[1].count)
        var leftLow = leftLowFilter.process(Array(channels[0].prefix(count)))
        var rightLow = rightLowFilter.process(Array(channels[1].prefix(count)))
        let leftHigh = leftHighFilter.process(Array(channels[0].prefix(count)))
        let rightHigh = rightHighFilter.process(Array(channels[1].prefix(count)))
        for i in 0..<count {
            let lowMid = (leftLow[i] + rightLow[i]) * 0.5
            leftLow[i] = leftLow[i] * (1 - amount) + lowMid * amount
            rightLow[i] = rightLow[i] * (1 - amount) + lowMid * amount
        }
        var output = channels
        output[0] = (0..<count).map { leftLow[$0] + leftHigh[$0] }
        output[1] = (0..<count).map { rightLow[$0] + rightHigh[$0] }
        return output
    }

    /// Onset-aware high-band emphasis. It follows the signal envelope instead of applying
    /// a static bright EQ, so sustained hiss is not boosted together with attacks.
    private static func recoverTransients(_ channels: [[Float]], sampleRate: Float, strength: Float, preset: ContentPreset) -> [[Float]] {
        let amount = max(0, min(1, preset.transientAmount * strength))
        guard amount > 0.01 else { return channels }
        var output: [[Float]] = []
        for channel in channels {
            let transientBand = Biquad(BiquadCoefficients.highPass(sampleRate: sampleRate, frequency: 1700, q: 0.72)).process(channel)
            let blockSize = max(64, Int(sampleRate * 0.012))
            var result = channel
            var previousEnvelope: Float = 0
            var start = 0
            while start < channel.count {
                let end = min(channel.count, start + blockSize)
                var sum: Float = 0
                vDSP_svesq(Array(transientBand[start..<end]), 1, &sum, vDSP_Length(end - start))
                let envelope = sqrt(sum / Float(max(1, end - start)))
                let onset = max(0, envelope - previousEnvelope)
                let attackRatio = onset / max(envelope, 1e-7)
                let emphasis = min(1.7, attackRatio * 2.2)
                let addAmount = 0.20 * amount * emphasis
                for i in start..<end { result[i] += transientBand[i] * addAmount }
                previousEnvelope = envelope
                start = end
            }
            output.append(result)
        }
        return output
    }

    private static func matchReferenceBands(_ channels: [[Float]], reference: [[Float]], sampleRate: Float, strength: Float) -> [[Float]] {
        let target = DSP.averageSpectrum(channels: channels, sampleRate: sampleRate)
        let source = DSP.averageSpectrum(channels: reference, sampleRate: sampleRate)
        guard !target.isEmpty, !source.isEmpty else { return channels }
        let bands: [(String, Float, Float)] = [
            ("sub", 20, 60), ("low", 60, 120), ("lowmid", 120, 350), ("mid", 350, 2000),
            ("highmid", 2000, 6000), ("high", 6000, 10000), ("air", 10000, min(16000, sampleRate / 2 - 1))
        ]
        var filters: [(Float, Float, Float)] = []
        for band in bands where band.1 < band.2 && band.2 < sampleRate / 2 {
            func averagePowerDb(_ spectrum: [(frequency: Float, powerDb: Float)]) -> Float {
                let values = spectrum.filter { $0.frequency >= band.1 && $0.frequency < band.2 }
                guard !values.isEmpty else { return -100 }
                let linear = values.map { pow(10, $0.powerDb / 10) }.reduce(0, +)
                return DSP.db(sqrt(linear / Float(values.count)))
            }
            let difference = averagePowerDb(source) - averagePowerDb(target)
            let gain = max(-5, min(5, difference)) * strength
            let center = sqrt(band.1 * band.2)
            if abs(gain) > 0.25 {
                if band.0 == "sub" {
                    filters.append((60, gain, 0.7))
                } else if band.0 == "air" {
                    filters.append((11000, gain, 0.7))
                } else {
                    filters.append((center, gain, 1.0))
                }
            }
        }
        var output: [[Float]] = []
        for channel in channels {
            var y = channel
            for (frequency, gain, q) in filters {
                let filter: Biquad
                if frequency <= 60 {
                    filter = Biquad(BiquadCoefficients.lowShelf(sampleRate: sampleRate, frequency: frequency, gain: gain, q: q))
                } else if frequency >= 10500 {
                    filter = Biquad(BiquadCoefficients.highShelf(sampleRate: sampleRate, frequency: frequency, gain: gain, q: q))
                } else {
                    filter = Biquad(BiquadCoefficients.peaking(sampleRate: sampleRate, frequency: frequency, gain: gain, q: q))
                }
                y = filter.process(y)
            }
            output.append(y)
        }
        return output
    }

    private static func addAirAndDetail(_ channels: [[Float]], sampleRate: Float, strength: Float, preset: ContentPreset) -> [[Float]] {
        guard sampleRate / 2 > 12000 else { return channels }
        var output: [[Float]] = []
        for channel in channels {
            let high = Biquad(BiquadCoefficients.highPass(sampleRate: sampleRate, frequency: 3000, q: 0.7)).process(channel)
            var harmonic = high
            for i in 0..<harmonic.count {
                let x = harmonic[i] * 2.0
                harmonic[i] = tanh(x) * (0.14 + preset.airGain * 0.06) * strength
            }
            var mixed = channel
            for i in 0..<mixed.count { mixed[i] += harmonic[i] }
            let air = Biquad(BiquadCoefficients.highShelf(sampleRate: sampleRate, frequency: 10500, gain: max(0.3, preset.airGain) * strength, q: 0.7)).process(mixed)
            output.append(air)
        }
        return output
    }
}
