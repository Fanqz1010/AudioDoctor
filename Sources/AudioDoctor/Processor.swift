import Foundation

struct RepairOptions {
    var deHiss = true
    var fullness = true
    var matchReference = true
    var exciter = true
    var loudnessNormalize = true
    var targetLUFS: Float = -14
    var strength: Float = 1.0
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

        if options.deHiss {
            output = deHiss(output, sampleRate: sampleRate, strength: strength)
        }
        if options.fullness {
            if let referenceChannels, options.matchReference {
                output = matchReferenceBands(output, reference: referenceChannels, sampleRate: sampleRate, strength: strength)
            } else {
                output = addFullness(output, sampleRate: sampleRate, strength: strength)
            }
        }
        if options.exciter {
            output = addAirAndDetail(output, sampleRate: sampleRate, strength: strength)
        }
        if options.loudnessNormalize, let lufs = DSP.kWeightedLUFS(channels: output, sampleRate: sampleRate) {
            let gainDb = options.targetLUFS - lufs
            let gain = pow(10, gainDb / 20)
            DSP.applyGain(&output, gain: gain)
            DSP.limit(&output, sampleRate: sampleRate, ceiling: pow(10, -1 / 20))
        } else {
            DSP.limit(&output, sampleRate: sampleRate, ceiling: pow(10, -1 / 20))
        }
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

    private static func deHiss(_ channels: [[Float]], sampleRate: Float, strength: Float) -> [[Float]] {
        let cutoff = min(8500, sampleRate / 2 - 100)
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
            var reductionDb = -7.0 * strength
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

    private static func addFullness(_ channels: [[Float]], sampleRate: Float, strength: Float) -> [[Float]] {
        let eqs: [(Float, Float, Float, Float)] = [
            (55, 2.2, 0.7, 1), (105, 1.4, 0.7, 1), (260, 0.7, 0.8, 1), (3200, -0.8, 1.0, 1)
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

    private static func addAirAndDetail(_ channels: [[Float]], sampleRate: Float, strength: Float) -> [[Float]] {
        guard sampleRate / 2 > 12000 else { return channels }
        var output: [[Float]] = []
        for channel in channels {
            let high = Biquad(BiquadCoefficients.highPass(sampleRate: sampleRate, frequency: 3000, q: 0.7)).process(channel)
            var harmonic = high
            for i in 0..<harmonic.count {
                let x = harmonic[i] * 2.0
                harmonic[i] = tanh(x) * 0.22 * strength
            }
            var mixed = channel
            for i in 0..<mixed.count { mixed[i] += harmonic[i] }
            let air = Biquad(BiquadCoefficients.highShelf(sampleRate: sampleRate, frequency: 10500, gain: 1.6 * strength, q: 0.7)).process(mixed)
            output.append(air)
        }
        return output
    }
}
