import Foundation

enum LabelLevel: String, CaseIterable {
    case pass = "通过"
    case review = "复核"
    case fail = "异常"

    var sortOrder: Int {
        switch self {
        case .pass: return 0
        case .review: return 1
        case .fail: return 2
        }
    }
}

struct LabelCriterion: Identifiable {
    var id: String { name }
    let name: String
    let category: String
    let value: String
    let standard: String
    let interpretation: String
    let level: LabelLevel
    let score: Float
}

struct LabelAssessment {
    let grade: String
    let verdict: String
    let criteria: [LabelCriterion]

    var level: LabelLevel {
        criteria.map(\.level).max { $0.sortOrder < $1.sortOrder } ?? .pass
    }

    var failedNames: [String] {
        criteria.filter { $0.level == .fail }.map(\.name)
    }

    var reviewNames: [String] {
        criteria.filter { $0.level == .review }.map(\.name)
    }
}

enum LabelStandards {
    /// Transparent, rule-based thresholds for annotation teams. These are not
    /// aesthetic judgments; they describe measurable technical risk.
    static func assess(_ report: AudioAnalysisReport) -> LabelAssessment {
        var criteria: [LabelCriterion] = []

        if let lufs = report.integratedLUFS {
            let level: LabelLevel
            switch lufs {
            case -16...(-12): level = .pass
            case -20...(-16), (-12)...(-9): level = .review
            default: level = .fail
            }
            criteria.append(.init(
                name: "综合响度 LUFS",
                category: "响度",
                value: String(format: "%.1f LUFS", lufs),
                standard: "流媒体常用 -16 ～ -12 LUFS；本工具以 -14 LUFS 为中心",
                interpretation: lufs < -16 ? "响度偏轻，标注员容易误判为音量弱或内容不完整。" : (lufs > -12 ? "响度偏响，可能压缩过度或平台播放会被限幅。" : "响度在常用分发范围内。"),
                level: level,
                score: max(0, min(100, 100 - abs(lufs + 14) * 8))
            ))
        }

        let truePeakLevel: LabelLevel
        switch report.truePeakDb {
        case ..<(-1.0): truePeakLevel = .pass
        case (-1.0)...0: truePeakLevel = .review
        default: truePeakLevel = .fail
        }
        criteria.append(.init(
            name: "真峰 dBTP",
            category: "失真风险",
            value: String(format: "%.2f dBTP", report.truePeakDb),
            standard: "建议 ≤ -1.0 dBTP；0 dBTP 以上判为异常",
            interpretation: report.truePeakDb <= -1 ? "转码/播放时留有安全峰值余量。" : "峰值余量不足，编码后可能出现失真。",
            level: truePeakLevel,
            score: report.truePeakDb <= -1 ? 100 : max(0, 100 + report.truePeakDb * 35)
        ))

        let clippingLevel: LabelLevel
        switch report.clippingPercent {
        case 0...0.001: clippingLevel = .pass
        case 0.001...0.05: clippingLevel = .review
        default: clippingLevel = .fail
        }
        criteria.append(.init(
            name: "削波采样占比",
            category: "失真风险",
            value: String(format: "%.4f%%", report.clippingPercent),
            standard: "≤0.001% 通过；0.001%～0.05% 复核；>0.05% 异常",
            interpretation: report.clippingPercent > 0.05 ? "削波比例较高，通常对应硬失真或过度限幅。" : "未见明显连续削波。",
            level: clippingLevel,
            score: max(0, 100 - report.clippingPercent * 1200)
        ))

        let crestLevel: LabelLevel
        switch report.crestFactorDb {
        case 4.5...14: crestLevel = .pass
        case 3...4.5, 14...18: crestLevel = .review
        default: crestLevel = .fail
        }
        criteria.append(.init(
            name: "动态余量 / 峰值因子",
            category: "动态",
            value: String(format: "%.1f dB", report.crestFactorDb),
            standard: "常见健康区间 4.5 ～ 14 dB",
            interpretation: report.crestFactorDb < 4.5 ? "动态很平，可能过度压缩/限幅。" : (report.crestFactorDb > 14 ? "动态很大，需注意弱段落可听性。" : "动态处于常见音乐/语音范围。"),
            level: crestLevel,
            score: max(0, min(100, 100 - abs(report.crestFactorDb - 9) * 9))
        ))

        let dcLevel: LabelLevel
        switch abs(report.dcOffset) {
        case 0...0.001: dcLevel = .pass
        case 0.001...0.005: dcLevel = .review
        default: dcLevel = .fail
        }
        criteria.append(.init(
            name: "直流偏移",
            category: "基础质量",
            value: String(format: "%.4f", report.dcOffset),
            standard: "绝对值 ≤0.001 通过；≤0.005 复核；更高异常",
            interpretation: abs(report.dcOffset) > 0.005 ? "直流偏移明显，会浪费 headroom 并影响 RMS 判断。" : "直流偏移可忽略。",
            level: dcLevel,
            score: max(0, 100 - abs(report.dcOffset) * 18000)
        ))

        if let correlation = report.stereoCorrelation {
            let phaseLevel: LabelLevel
            switch correlation {
            case 0.25...0.90: phaseLevel = .pass
            case 0.05...0.25, 0.90...1.0: phaseLevel = .review
            default: phaseLevel = .fail
            }
            criteria.append(.init(
                name: "相位相关性",
                category: "空间与兼容",
                value: String(format: "%.2f", correlation),
                standard: "0.25 ～ 0.90 通常较安全；负值为高风险",
                interpretation: correlation < 0.05 ? "左右声道严重反相或极宽，单声道折叠可能抵消。" : (correlation > 0.90 ? "接近单声道，空间展开有限。" : "相位安全，单声道兼容性较好。"),
                level: phaseLevel,
                score: correlation >= 0.25 && correlation <= 0.90 ? 100 : max(0, 100 - abs(correlation - 0.575) * 140)
            ))
        } else {
            criteria.append(.init(
                name: "相位相关性",
                category: "空间与兼容",
                value: "单声道",
                standard: "单声道不做立体声相位判断",
                interpretation: "无立体声折叠风险，但也没有左右展开信息。",
                level: .pass,
                score: 100
            ))
        }

        if let balance = report.channelBalanceDb {
            let level: LabelLevel = abs(balance) <= 1 ? .pass : (abs(balance) <= 3 ? .review : .fail)
            criteria.append(.init(
                name: "左右声道电平差",
                category: "空间与兼容",
                value: String(format: "%+.2f dB", balance),
                standard: "≤1 dB 通过；1～3 dB 复核；>3 dB 异常（正值=左声道更响）",
                interpretation: abs(balance) > 3 ? "左右声道明显不平衡，会影响声像位置判断。" : "左右电平平衡。",
                level: level,
                score: max(0, 100 - abs(balance) * 25)
            ))
        }

        if let foldDown = report.monoFoldDownLossDb {
            let level: LabelLevel = foldDown >= -1 ? .pass : (foldDown >= -3 ? .review : .fail)
            criteria.append(.init(
                name: "单声道折叠损失",
                category: "空间与兼容",
                value: String(format: "%.2f dB", foldDown),
                standard: "损失 ≥-1 dB 通过；-3 ～ -1 dB 复核；<-3 dB 异常",
                interpretation: foldDown < -3 ? "立体声转单声道时能量大幅抵消，需标注为兼容风险。" : "单声道折叠能量损失可控。",
                level: level,
                score: max(0, min(100, 100 + foldDown * 18))
            ))
        }

        if let spatial = report.spatialScore {
            let level: LabelLevel = spatial >= 70 ? .pass : (spatial >= 45 ? .review : .fail)
            criteria.append(.init(
                name: "空间展开指数",
                category: "空间与兼容",
                value: String(format: "%.0f / 100", spatial),
                standard: "≥70 通过；45～69 复核；<45 异常",
                interpretation: "由立体声宽度和相位安全度组成，是客观空间指标，不等同于听感好坏。",
                level: level,
                score: spatial
            ))
        }

        let lowEnergy = report.bandEnergies
            .filter { $0.lowHz >= 20 && $0.highHz <= 350 }
            .map(\.energyPercent).reduce(0, +)
        let lowLevel: LabelLevel = lowEnergy >= 15 && lowEnergy <= 50 ? .pass : .review
        criteria.append(.init(
            name: "低频/身体感能量",
            category: "频段平衡",
            value: String(format: "%.1f%%", lowEnergy),
            standard: "20～350Hz 能量占比 15%～50% 复核内；<15% 提示偏薄",
            interpretation: lowEnergy < 15 ? "低频能量不足，常被听感描述为薄、假、没有身体感。" : "低频能量在复核范围内。",
            level: lowLevel,
            score: max(0, min(100, 100 - abs(lowEnergy - 32) * 3))
        ))

        if let hiss = report.hissRatioDb {
            let level: LabelLevel = hiss <= -18 ? .pass : (hiss <= -12 ? .review : .fail)
            criteria.append(.init(
                name: "高频噪声占比",
                category: "噪声 / AI 感",
                value: String(format: "%.1f dB", hiss),
                standard: "≤-18 dB 通过；-18～-12 dB 复核；>-12 dB 异常",
                interpretation: hiss > -12 ? "9kHz 以上能量偏多，可能存在沙沙声或高频伪影。" : "高频噪声占比可控。",
                level: level,
                score: max(0, min(100, (hiss + 25) * 7))
            ))
        }

        if let aiFeel = report.aiFeelScore {
            let level: LabelLevel = aiFeel <= 35 ? .pass : (aiFeel <= 65 ? .review : .fail)
            criteria.append(.init(
                name: "疑似 AI 感指数",
                category: "噪声 / AI 感",
                value: String(format: "%.0f / 100", aiFeel),
                standard: "≤35 通过；35～65 复核；>65 异常",
                interpretation: "启发式指标：由低频偏薄和高频噪声占比推得，不能替代人工听感。",
                level: level,
                score: 100 - aiFeel
            ))
        }

        let failCount = criteria.filter { $0.level == .fail }.count
        let reviewCount = criteria.filter { $0.level == .review }.count
        let grade: String
        let verdict: String
        if failCount > 0 {
            grade = "D"
            verdict = "技术异常：建议先修复，再交给标注员"
        } else if reviewCount > 2 {
            grade = "C"
            verdict = "需复核：技术指标存在多项边界风险"
        } else if reviewCount > 0 {
            grade = "B"
            verdict = "可标注：个别指标建议人工复核"
        } else {
            grade = "A"
            verdict = "可标注：客观技术指标通过"
        }
        return LabelAssessment(grade: grade, verdict: verdict, criteria: criteria)
    }
}
