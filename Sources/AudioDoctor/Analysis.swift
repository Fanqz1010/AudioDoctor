import Foundation

struct AudioAnalysisReport: Codable {
    var filename: String
    var sampleRate: Float
    var channels: Int
    var durationSeconds: Double
    var integratedLUFS: Float?
    var samplePeakDb: Float
    var truePeakDb: Float
    var rmsDb: Float
    var crestFactorDb: Float
    var dcOffset: Float
    var clippedSamples: Int
    var stereoCorrelation: Float?
    var stereoWidthPercent: Float?
    var phaseRisk: String
    var hissRatioDb: Float?
    var spectralFlatness: Float?
    var bandEnergies: [BandEnergy]
    var thinnessScore: Float?
    var aiFeelScore: Float?
    var distortionRisk: String
    var recommendations: [String]

    struct BandEnergy: Codable, Identifiable {
        var id: String { name }
        var name: String
        var lowHz: Float
        var highHz: Float
        var energyPercent: Float
    }
}

enum AudioAnalyzer {
    static func analyze(channels: [[Float]], sampleRate: Float, filename: String) -> AudioAnalysisReport {
        let count = channels.map(\.count).min() ?? 0
        let duration = Double(count) / Double(sampleRate)
        let mono = channels.count == 1
        let left = channels[0]
        let right = mono ? channels[0] : channels[1]

        let samplePeak = DSP.peak(left + right)
        let truePeak = DSP.truePeakEstimate(channels)
        let rmsValue = DSP.rms(left + right)
        let crest = DSP.db(samplePeak) - DSP.db(rmsValue)
        let dc = (left.reduce(0, +) + right.reduce(0, +)) / Float(max(1, 2 * count))
        var clipped = 0
        for channel in channels {
            for sample in channel where abs(sample) >= 0.998 { clipped += 1 }
        }

        let correlation = mono ? nil : DSP.correlation(left, right)
        var mid = [Float](repeating: 0, count: count)
        var side = [Float](repeating: 0, count: count)
        if !mono {
            for i in 0..<count {
                mid[i] = (left[i] + right[i]) * 0.5
                side[i] = (left[i] - right[i]) * 0.5
            }
        }
        let midRms = mono ? DSP.rms(left) : DSP.rms(mid)
        let sideRms = mono ? 0 : DSP.rms(side)
        let width = mono ? 0 : sideRms / max(midRms + sideRms, 1e-9) * 100
        var phaseRisk = "单声道，无相位风险"
        if let corr = correlation {
            if corr < -0.2 { phaseRisk = "高风险：左右声道明显反相" }
            else if corr < 0.25 { phaseRisk = "中风险：立体声较宽，单声道兼容性需注意" }
            else if corr < 0.85 { phaseRisk = "正常：立体声展开适度" }
            else { phaseRisk = "偏窄：接近单声道" }
        }

        let spectrum = DSP.averageSpectrum(channels: channels, sampleRate: sampleRate)
        let bands: [(String, Float, Float)] = [
            ("超低", 20, 60), ("低频", 60, 120), ("中低", 120, 350), ("中频", 350, 2000),
            ("中高频", 2000, 6000), ("高频", 6000, 10000), ("空气感", 10000, 16000), ("超声波段", 16000, min(20000, sampleRate / 2 - 1))
        ]
        let powers = spectrum.map { $0.powerDb }
        let linearPowers = powers.map { pow(10, $0 / 10) }
        let total = linearPowers.reduce(0, +)
        var bandEnergies: [AudioAnalysisReport.BandEnergy] = []
        for band in bands where band.1 < band.2 {
            let bandPower = spectrum.filter { $0.frequency >= band.1 && $0.frequency < band.2 }.map { pow(10, $0.powerDb / 10) }.reduce(0, +)
            bandEnergies.append(.init(name: band.0, lowHz: band.1, highHz: band.2, energyPercent: total > 0 ? bandPower / total * 100 : 0))
        }
        let hissPower = spectrum.filter { $0.frequency >= 9000 }.map { pow(10, $0.powerDb / 10) }.reduce(0, +)
        let hissRatio = total > 0 ? DSP.db(sqrt(hissPower / total)) : nil
        let positivePowers = linearPowers.filter { $0 > 0 }
        let logSum = positivePowers.map { log($0) }.reduce(0, +)
        let geometric = exp(logSum / Float(max(1, positivePowers.count)))
        let arithmetic = total / Float(max(1, positivePowers.count))
        let flatness = arithmetic > 0 ? geometric / arithmetic : nil

        let lowEnergy = bandEnergies.filter { $0.lowHz >= 20 && $0.highHz <= 350 }.map(\.energyPercent).reduce(0, +)
        let thinness = max(0, min(100, (30 - lowEnergy) / 30 * 100))
        let highRatioDb = hissRatio ?? -60
        let aiFeel = max(0, min(100, thinness * 0.55 + max(0, (highRatioDb + 18) / 18) * 45))
        let distortionRisk: String
        if clipped > count / 100 || DSP.db(samplePeak) > -0.1 || DSP.db(truePeak) > 0 {
            distortionRisk = "高：存在削波或超采样峰值"
        } else if clipped > count / 1000 || DSP.db(truePeak) > -0.3 {
            distortionRisk = "中：接近削波，导出前建议保留真峰限制"
        } else {
            distortionRisk = "低：未发现明显削波"
        }

        var recommendations: [String] = []
        if lowEnergy < 15 { recommendations.append("低频不足，建议使用「丰满修复」或导入参考曲匹配。") }
        if highRatioDb > -12 { recommendations.append("高频沙沙声偏多，建议开启「去沙声」。") }
        if let corr = correlation, corr < 0.25 { recommendations.append("相位风险较高，转换单声道前请先试听。") }
        if clipped > count / 100 || DSP.db(truePeak) > 0 { recommendations.append("建议开启真峰限制，目标 -1 dBTP。") }
        if crest < 4.5 { recommendations.append("峰值因子很低，建议检查是否过度限幅。") }
        if recommendations.isEmpty { recommendations.append("整体指标健康，可按需要做响度标准化或声道转换。") }

        return AudioAnalysisReport(
            filename: filename,
            sampleRate: sampleRate,
            channels: channels.count,
            durationSeconds: duration,
            integratedLUFS: DSP.kWeightedLUFS(channels: channels, sampleRate: sampleRate),
            samplePeakDb: DSP.db(samplePeak),
            truePeakDb: DSP.db(truePeak),
            rmsDb: DSP.db(rmsValue),
            crestFactorDb: crest,
            dcOffset: dc,
            clippedSamples: clipped,
            stereoCorrelation: correlation,
            stereoWidthPercent: mono ? nil : width,
            phaseRisk: phaseRisk,
            hissRatioDb: hissRatio,
            spectralFlatness: flatness,
            bandEnergies: bandEnergies,
            thinnessScore: thinness,
            aiFeelScore: aiFeel,
            distortionRisk: distortionRisk,
            recommendations: recommendations
        )
    }
}
