import Accelerate
import Foundation

struct BiquadCoefficients {
    var b0: Float, b1: Float, b2: Float, a1: Float, a2: Float

    static func highShelf(sampleRate: Float, frequency: Float, gain: Float, q: Float) -> BiquadCoefficients {
        let k = tan(Float.pi * frequency / sampleRate)
        let vh = pow(10, gain / 20)
        let vb = pow(vh, 0.4996667741545416)
        let denom = 1 + k / q + k * k
        return BiquadCoefficients(
            b0: (vh + vb * k / q + k * k) / denom,
            b1: 2 * (k * k - vh) / denom,
            b2: (vh - vb * k / q + k * k) / denom,
            a1: 2 * (k * k - 1) / denom,
            a2: (1 - k / q + k * k) / denom
        )
    }

    static func lowShelf(sampleRate: Float, frequency: Float, gain: Float, q: Float) -> BiquadCoefficients {
        let a = pow(10, gain / 40)
        let omega = 2 * Float.pi * frequency / sampleRate
        let alpha = sin(omega) / (2 * q)
        let cosine = cos(omega)
        let denom = (a + 1) + (a - 1) * cosine + 2 * sqrt(a) * alpha
        return BiquadCoefficients(
            b0: a * ((a + 1) - (a - 1) * cosine + 2 * sqrt(a) * alpha) / denom,
            b1: 2 * a * ((a - 1) - (a + 1) * cosine) / denom,
            b2: a * ((a + 1) - (a - 1) * cosine - 2 * sqrt(a) * alpha) / denom,
            a1: -2 * ((a - 1) + (a + 1) * cosine) / denom,
            a2: ((a + 1) + (a - 1) * cosine - 2 * sqrt(a) * alpha) / denom
        )
    }

    static func peaking(sampleRate: Float, frequency: Float, gain: Float, q: Float) -> BiquadCoefficients {
        let k = tan(Float.pi * frequency / sampleRate)
        let vh = pow(10, gain / 20)
        let denom = 1 + k / q + k * k
        return BiquadCoefficients(
            b0: (1 + vh * k / q + k * k) / denom,
            b1: 2 * (k * k - 1) / denom,
            b2: (1 - vh * k / q + k * k) / denom,
            a1: 2 * (k * k - 1) / denom,
            a2: (1 - k / q + k * k) / denom
        )
    }

    static func highPass(sampleRate: Float, frequency: Float, q: Float = 0.7071) -> BiquadCoefficients {
        let k = tan(Float.pi * frequency / sampleRate)
        let denom = 1 + k / q + k * k
        return BiquadCoefficients(
            b0: 1 / denom,
            b1: -2 / denom,
            b2: 1 / denom,
            a1: 2 * (k * k - 1) / denom,
            a2: (1 - k / q + k * k) / denom
        )
    }

    static func lowPass(sampleRate: Float, frequency: Float, q: Float = 0.7071) -> BiquadCoefficients {
        let k = tan(Float.pi * frequency / sampleRate)
        let denom = 1 + k / q + k * k
        return BiquadCoefficients(
            b0: k * k / denom,
            b1: 2 * k * k / denom,
            b2: k * k / denom,
            a1: 2 * (k * k - 1) / denom,
            a2: (1 - k / q + k * k) / denom
        )
    }
}

final class Biquad {
    private var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0
    private var coefficients: BiquadCoefficients

    init(_ coefficients: BiquadCoefficients) {
        self.coefficients = coefficients
    }

    func reset() {
        x1 = 0; x2 = 0; y1 = 0; y2 = 0
    }

    func process(_ input: [Float]) -> [Float] {
        var output = [Float](repeating: 0, count: input.count)
        for i in 0..<input.count {
            let x0 = input[i]
            let y0 = coefficients.b0 * x0 + coefficients.b1 * x1 + coefficients.b2 * x2 - coefficients.a1 * y1 - coefficients.a2 * y2
            x2 = x1; x1 = x0; y2 = y1; y1 = y0
            output[i] = y0
        }
        return output
    }

    func processInPlace(_ samples: inout [Float]) {
        for i in 0..<samples.count {
            let x0 = samples[i]
            let y0 = coefficients.b0 * x0 + coefficients.b1 * x1 + coefficients.b2 * x2 - coefficients.a1 * y1 - coefficients.a2 * y2
            x2 = x1; x1 = x0; y2 = y1; y1 = y0
            samples[i] = y0
        }
    }
}

enum DSP {
    static func rms(_ x: [Float]) -> Float {
        guard !x.isEmpty else { return 0 }
        var sum: Float = 0
        vDSP_svesq(x, 1, &sum, vDSP_Length(x.count))
        return sqrt(sum / Float(x.count))
    }

    static func peak(_ x: [Float]) -> Float {
        guard !x.isEmpty else { return 0 }
        var value: Float = 0
        var signedPeak: Float = 0
        var magnitudeIndex = vDSP_Length(0)
        var signedIndex = vDSP_Length(0)
        vDSP_maxmgvi(x, 1, &value, &magnitudeIndex, vDSP_Length(x.count))
        vDSP_maxvi(x, 1, &signedPeak, &signedIndex, vDSP_Length(x.count))
        return value
    }

    static func db(_ linear: Float) -> Float {
        linear <= 0 ? -120 : 20 * log10(linear)
    }

    static func correlation(_ a: [Float], _ b: [Float]) -> Float? {
        let n = min(a.count, b.count)
        guard n > 1 else { return nil }
        var ma: Float = 0, mb: Float = 0
        vDSP_meanv(a, 1, &ma, vDSP_Length(n))
        vDSP_meanv(b, 1, &mb, vDSP_Length(n))
        var num: Float = 0, da: Float = 0, db: Float = 0
        for i in 0..<n {
            let x = a[i] - ma, y = b[i] - mb
            num += x * y; da += x * x; db += y * y
        }
        guard da > 0, db > 0 else { return nil }
        return num / sqrt(da * db)
    }

    static func kWeightedLUFS(channels: [[Float]], sampleRate: Float) -> Float? {
        let shelf = Biquad(BiquadCoefficients.highShelf(
            sampleRate: sampleRate,
            frequency: 1681.9744509555319,
            gain: 3.999843853973347,
            q: 0.7071752369554196
        ))
        let highPass = Biquad(BiquadCoefficients.highPass(
            sampleRate: sampleRate,
            frequency: 38.13547087602444,
            q: 0.5003270373238773
        ))
        let weights: [Float] = [1, 1, 1, 1.41, 1.41]
        let weightedChannels = channels.enumerated().map { index, channel -> [Float] in
            var y = shelf.process(channel)
            highPass.processInPlace(&y)
            let w = index < weights.count ? weights[index] : 1
            // BS.1770 channel weights are power weights, so scale amplitude by sqrt(weight).
            if w != 1 {
                var scalar = sqrt(w)
                var scaled = [Float](repeating: 0, count: y.count)
                vDSP_vsmul(y, 1, &scalar, &scaled, 1, vDSP_Length(y.count))
                y = scaled
            }
            return y
        }

        let blockSize = Int(sampleRate * 0.4)
        let hop = blockSize / 4
        guard blockSize > 0, weightedChannels.allSatisfy({ $0.count >= blockSize }) else { return nil }
        var blockPowers: [Float] = []
        var start = 0
        while start + blockSize <= (weightedChannels.first?.count ?? 0) {
            var power: Float = 0
            for channel in weightedChannels {
                var sum: Float = 0
                vDSP_svesq(Array(channel[start..<(start+blockSize)]), 1, &sum, vDSP_Length(blockSize))
                power += sum / Float(blockSize)
            }
            if power > 0 { blockPowers.append(power) }
            start += hop
        }
        guard !blockPowers.isEmpty else { return nil }
        let blockLoudness = blockPowers.map { -0.691 + 10 * log10($0) }
        let absolutelyGated = zip(blockPowers, blockLoudness).filter { $0.1 > -70 }
        guard !absolutelyGated.isEmpty else { return nil }
        let firstMeanPower = absolutelyGated.map(\.0).reduce(0, +) / Float(absolutelyGated.count)
        let relativeThreshold = -0.691 + 10 * log10(firstMeanPower) - 10
        let retainedPowers = zip(blockPowers, blockLoudness)
            .filter { $0.1 > -70 && $0.1 > relativeThreshold }
            .map(\.0)
        guard !retainedPowers.isEmpty else { return nil }
        let totalPower = retainedPowers.reduce(0, +)
        return -0.691 + 10 * log10(totalPower / Float(retainedPowers.count))
    }

    static func averageSpectrum(channels: [[Float]], sampleRate: Float, fftSize: Int = 4096, maxFrames: Int = 240) -> [(frequency: Float, powerDb: Float)] {
        var averages = [Float](repeating: 0, count: fftSize / 2 + 1)
        var frames = 0
        let hop = fftSize / 2
        for channel in channels {
            var start = 0
            while start + fftSize <= channel.count && frames < maxFrames {
                var frame = Array(channel[start..<(start + fftSize)])
                let mean = frame.reduce(0, +) / Float(frame.count)
                for i in 0..<frame.count { frame[i] -= mean }
                let window = DSP.hannWindow(fftSize)
                vDSP_vmul(frame, 1, window, 1, &frame, 1, vDSP_Length(fftSize))
                let spectrum = DSP.realFFTMagnitudes(frame)
                for i in 0..<averages.count { averages[i] += spectrum[i] * spectrum[i] }
                frames += 1
                start += hop * 4
            }
        }
        guard frames > 0 else { return [] }
        vDSP_vsdiv(averages, 1, [Float(frames)], &averages, 1, vDSP_Length(averages.count))
        return averages.enumerated().map { index, power in
            (Float(index) * sampleRate / Float(fftSize), DSP.db(sqrt(power)))
        }
    }

    static func hannWindow(_ n: Int) -> [Float] {
        (0..<n).map { 0.5 * (1 - cos(2 * Float.pi * Float($0) / Float(n))) }
    }

    static func realFFTMagnitudes(_ input: [Float]) -> [Float] {
        let n = input.count
        guard n > 1, n & (n - 1) == 0 else { return [] }
        var real = input
        var imaginary = [Float](repeating: 0, count: n)
        real.withUnsafeMutableBufferPointer { realPointer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                var split = DSPSplitComplex(realp: realPointer.baseAddress!, imagp: imaginaryPointer.baseAddress!)
                if let setup = vDSP_create_fftsetup(vDSP_Length(log2(Float(n))), FFTRadix(kFFTRadix2)) {
                    vDSP_fft_zip(setup, &split, 1, vDSP_Length(log2(Float(n))), FFTDirection(FFT_FORWARD))
                    vDSP_destroy_fftsetup(setup)
                }
            }
        }
        let half = n / 2
        var magnitudes = [Float](repeating: 0, count: half + 1)
        magnitudes[0] = abs(real[0])
        for i in 1..<half {
            magnitudes[i] = sqrt(real[i] * real[i] + imaginary[i] * imaginary[i])
        }
        magnitudes[half] = abs(real[half])
        return magnitudes
    }

    static func truePeakEstimate(_ channels: [[Float]]) -> Float {
        var maximum: Float = 0
        for channel in channels {
            guard channel.count > 2 else { continue }
            var i = 0
            while i < channel.count {
                let next = min(i + 4096, channel.count - 1)
                if i == next { break }
                for j in i..<next {
                    let x0 = j == 0 ? channel[0] : channel[j - 1]
                    let x1 = channel[j]
                    let x2 = channel[j + 1]
                    let x3 = j + 2 < channel.count ? channel[j + 2] : channel[j + 1]
                    let a = -0.5*x0 + 1.5*x1 - 1.5*x2 + 0.5*x3
                    let b = x0 - 2.5*x1 + 2*x2 - 0.5*x3
                    let c = -0.5*x0 + 0.5*x2
                    for step in 1...3 {
                        let t = Float(step) / 4
                        let interpolated = ((a*t + b)*t + c)*t + x1
                        maximum = max(maximum, abs(interpolated))
                    }
                    maximum = max(maximum, abs(x1))
                }
                i = next
            }
        }
        return maximum
    }

    static func applyGain(_ channels: inout [[Float]], gain: Float) {
        var scalar = gain
        for i in 0..<channels.count {
            let source = channels[i]
            var destination = [Float](repeating: 0, count: source.count)
            vDSP_vsmul(source, 1, &scalar, &destination, 1, vDSP_Length(source.count))
            channels[i] = destination
        }
    }

    static func limit(_ channels: inout [[Float]], sampleRate: Float, ceiling: Float = 0.891250938) {
        guard !channels.isEmpty else { return }
        let count = channels[0].count
        guard count > 0 else { return }
        let lookahead = max(1, Int(sampleRate * 0.005))
        var envelope = [Float](repeating: 0, count: count)
        for channel in channels {
            for i in 0..<count {
                envelope[i] = max(envelope[i], abs(channel[i]))
            }
        }
        var gain = [Float](repeating: 1, count: count)
        var smoothedGain: Float = 1
        let attackCoefficient: Float = exp(-1 / (sampleRate * 0.001))
        let releaseCoefficient: Float = exp(-1 / (sampleRate * 0.050))
        for i in 0..<count {
            var futurePeak: Float = 0
            let end = min(count, i + lookahead)
            for j in i..<end { futurePeak = max(futurePeak, envelope[j]) }
            let requiredReduction = futurePeak > ceiling ? ceiling / futurePeak : 1
            if requiredReduction < smoothedGain {
                smoothedGain = max(requiredReduction, smoothedGain * attackCoefficient)
            } else {
                smoothedGain = min(1, smoothedGain + (1 - smoothedGain) * (1 - releaseCoefficient))
            }
            gain[i] = smoothedGain
        }
        for c in 0..<channels.count {
            for i in 0..<count { channels[c][i] *= gain[i] }
        }
    }
}
