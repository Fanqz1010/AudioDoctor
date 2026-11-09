import Foundation

struct BatchIssueCount: Codable, Identifiable, Equatable {
    var id: String { name }
    let name: String
    let count: Int
}

struct BatchWorstFile: Codable, Identifiable, Equatable {
    var id: String { fileName + "-" + String(rank) }
    let rank: Int
    let fileName: String
    let grade: String
    let verdict: String
    let artifactScore: Float?
    let failedChecks: [String]
    let reviewChecks: [String]
}

struct BatchAggregate: Codable, Equatable {
    let total: Int
    let gradeCounts: [String: Int]
    let issueCounts: [BatchIssueCount]
    let worstFiles: [BatchWorstFile]
    let recommendations: [String]

    static func summarize(records: [BatchRecord]) -> BatchAggregate {
        let successful = records.filter { $0.status != "失败" }
        var grades: [String: Int] = ["A": 0, "B": 0, "C": 0, "D": 0]
        for record in successful { grades[record.grade, default: 0] += 1 }

        var issueNames: [String: Int] = [:]
        for record in successful {
            for name in record.failedChecks { issueNames[name, default: 0] += 1 }
            for name in record.reviewChecks { issueNames[name, default: 0] += 1 }
            for interval in record.issueIntervals where interval.severity != "低" {
                issueNames[interval.issue, default: 0] += 1
            }
        }
        var issueList: [BatchIssueCount] = []
        for (name, count) in issueNames {
            let item = BatchIssueCount(name: name, count: count)
            issueList.append(item)
        }
        issueList.sort { left, right in
            if left.count == right.count { return left.name < right.name }
            return left.count > right.count
        }
        let issues: [BatchIssueCount] = issueList

        typealias WorstCandidate = (record: BatchRecord, priority: Int)
        var candidates: [WorstCandidate] = []
        for record in successful {
            let artifactScore: Float = record.artifactOverall ?? 0
            let artifactInteger: Int = Int(artifactScore.rounded())
            let failedWeight: Int = record.failedChecks.count * 1000
            let reviewWeight: Int = record.reviewChecks.count * 180
            let candidate: WorstCandidate = (record, failedWeight + reviewWeight + artifactInteger)
            if candidate.priority > 0 { candidates.append(candidate) }
        }
        candidates.sort { left, right in
            if left.priority == right.priority { return left.record.fileName < right.record.fileName }
            return left.priority > right.priority
        }

        var ranked: [BatchWorstFile] = []
        let maximumWorstFiles = min(20, candidates.count)
        for index in 0..<maximumWorstFiles {
            let item = candidates[index]
            let worst = BatchWorstFile(
                rank: index + 1,
                fileName: item.record.fileName,
                grade: item.record.grade,
                verdict: item.record.verdict,
                artifactScore: item.record.artifactOverall,
                failedChecks: item.record.failedChecks,
                reviewChecks: item.record.reviewChecks
            )
            ranked.append(worst)
        }

        var recommendations: [String] = []
        if grades["D", default: 0] > 0 { recommendations.append("优先处理 D 级文件：先解决削波、反相、响度越界等硬性技术问题。") }
        if let issue = issues.first, issue.count > 0 { recommendations.append("本批最集中问题是「\(issue.name)」（\(issue.count) 处/条），建议用同一修复参数先做小样本 A/B。") }
        if successful.contains(where: { ($0.artifactOverall ?? 0) > 65 }) { recommendations.append("AI 伪影总分 >65 的文件建议人工试听高频细节和鼓组瞬态，不要只看总分。") }
        if successful.contains(where: { $0.monoFoldDownLossDb ?? 0 < -3 }) { recommendations.append("存在单声道折叠损失：开启低频单声道化，并抽听手机/单声道播放。") }
        if records.filter({ $0.status == "失败" }).count > 0 { recommendations.append("读取失败文件需检查编码、损坏、权限或采样率支持，失败不会影响其它文件继续处理。") }
        if recommendations.isEmpty { recommendations.append("整体技术风险较低；可按内容风格执行轻量优化，并保留原始文件用于回退。") }
        let keyCounts = successful.compactMap(\.musicKey)
        if !keyCounts.isEmpty {
            var frequency: [String: Int] = [:]
            for key in keyCounts { frequency[key, default: 0] += 1 }
            if let commonKey = frequency.max(by: { $0.value < $1.value }) {
                recommendations.append("最常见调性为「\(commonKey.key)」（\(commonKey.value) 首）；同批次可优先用统一响度与频响策略，调性只作内容分析参考。")
            }
        }
        let bpmValues = successful.compactMap(\.tempoBPM)
        if bpmValues.count > 1 {
            let sortedBPM = bpmValues.sorted()
            let median = sortedBPM[sortedBPM.count / 2]
            recommendations.append("本批 BPM 中位数约 \(String(format: "%.1f", median))；如用于歌单或混编场景，建议同时检查 BPM 离散度。")
        }

        return BatchAggregate(
            total: records.count,
            gradeCounts: grades,
            issueCounts: Array(issues.prefix(12)),
            worstFiles: Array(ranked),
            recommendations: recommendations
        )
    }
}

enum BatchReportWriter {
    static func writeHTML(
        records: [BatchRecord],
        aggregate: BatchAggregate,
        csvURL: URL?,
        outputFolder: URL,
        cancelled: Bool
    ) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = outputFolder.appendingPathComponent("AudioDoctor-Batch-Report-\(formatter.string(from: Date())).html")
        var lines: [String] = []
        lines.append("<!doctype html><html lang=\"zh-CN\"><head><meta charset=\"utf-8\">")
        lines.append("<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"><title>Audio Doctor 批量体检报告</title>")
        lines.append("<style>:root{color-scheme:light dark;--line:#d8dee9;--muted:#64748b;--accent:#2563eb;--ok:#16a34a;--warn:#d97706;--bad:#dc2626}*{box-sizing:border-box}body{margin:0;padding:32px;font-family:-apple-system,BlinkMacSystemFont,\"PingFang SC\",sans-serif;line-height:1.55}.wrap{max-width:1480px;margin:0 auto}h1{margin:.2em 0;font-size:30px}h2{margin-top:34px;font-size:20px}.muted{color:var(--muted)}.small{font-size:12px}.cards{display:grid;grid-template-columns:repeat(6,minmax(100px,1fr));gap:10px;margin:22px 0}.card{border:1px solid var(--line);border-radius:12px;padding:14px;background:rgba(127,127,127,.04)}.card b{display:block;font-size:26px;margin-top:4px}table{width:100%;border-collapse:collapse;margin-top:10px;font-size:12px}th,td{border-bottom:1px solid var(--line);padding:8px 7px;text-align:left;vertical-align:top;white-space:nowrap}th{position:sticky;top:0;background:rgba(127,127,127,.08)}.table-scroll{overflow:auto;max-height:680px;border:1px solid var(--line);border-radius:10px}.A,.B,.C,.D{font-weight:700}.A{color:var(--ok)}.B{color:var(--accent)}.C{color:var(--warn)}.D{color:var(--bad)}.pill{display:inline-block;padding:2px 7px;border-radius:999px;background:rgba(127,127,127,.12);margin:1px}.note{border-left:4px solid var(--accent);padding:10px 14px;background:rgba(37,99,235,.07);border-radius:0 8px 8px 0}</style>")
        lines.append("</head><body><div class=\"wrap\"><div class=\"muted small\">Audio Doctor · 客观批量体检与 Badcase 定位</div>")
        lines.append("<h1>批量音频体检报告</h1>")
        let status = cancelled ? "已取消，已写入完成部分" : "完成"
        lines.append("<div>生成时间：\(Date().formatted()) · 状态：\(status)</div>")
        lines.append("<div class=\"cards\">")
        lines.append("<div class=\"card\">总数<b>\(aggregate.total)</b></div>")
        for grade in ["A", "B", "C", "D"] {
            lines.append("<div class=\"card\">\(grade) 级<b>\(aggregate.gradeCounts[grade, default: 0])</b></div>")
        }
        let failed = records.filter { $0.status == "失败" }.count
        lines.append("<div class=\"card\">读取失败<b>\(failed)</b></div></div>")
        lines.append("<div class=\"note\">标准边界：响度、真峰、削波、相位、频段占比和伪影指数是客观/启发式技术指标，用于定位风险和统一标注口径；它们不能完全替代人工听感，也不能作为 AI 来源检测或规避检测的依据。</div>")
        lines.append("<h2>处理建议</h2><ol>")
        for recommendation in aggregate.recommendations { lines.append("<li>\(escape(recommendation))</li>") }
        lines.append("</ol><h2>集中问题排序</h2><table><thead><tr><th>问题</th><th>出现次数</th></tr></thead><tbody>")
        for issue in aggregate.issueCounts { lines.append("<tr><td>\(escape(issue.name))</td><td>\(issue.count)</td></tr>") }
        lines.append("</tbody></table><h2>最需要优先复核的文件</h2><table><thead><tr><th>#</th><th>等级</th><th>文件</th><th>AI 伪影总分</th><th>问题</th></tr></thead><tbody>")
        for item in aggregate.worstFiles {
            let score = item.artifactScore.map { String(format: "%.0f", $0) } ?? "—"
            let pills = (item.failedChecks + item.reviewChecks).map { "<span class=\"pill\">\(escape($0))</span>" }.joined()
            lines.append("<tr><td>\(item.rank)</td><td class=\"\(item.grade)\">\(item.grade)</td><td>\(escape(item.fileName))</td><td>\(score)</td><td>\(pills)</td></tr>")
        }
        lines.append("</tbody></table><h2>全量明细</h2><div class=\"table-scroll\"><table><thead><tr><th>状态</th><th>等级</th><th>文件</th><th>调性</th><th>BPM</th><th>主奏推测</th><th>LUFS</th><th>dBTP</th><th>相位</th><th>低频%</th><th>沙声</th><th>金属感</th><th>空洞</th><th>瞬态</th><th>AI总分</th><th>失败/复核</th><th>时间定位</th><th>错误</th></tr></thead><tbody>")
        for record in records { lines.append(rowHTML(record)) }
        lines.append("</tbody></table></div>")
        let csvName = csvURL.map { escape($0.lastPathComponent) } ?? "未生成"
        lines.append("<p class=\"muted small\">CSV 明细：\(csvName)。原始音频不会被修改；修复导出文件会使用独立文件名。</p>")
        lines.append("</div></body></html>")
        try Data(lines.joined(separator: "\n").utf8).write(to: url, options: .atomic)
        return url
    }

    private static func rowHTML(_ record: BatchRecord) -> String {
        var values: [String] = []
        values.append(escape(record.status))
        values.append("<span class=\(record.grade)>\(record.grade)</span>")
        values.append(escape(record.fileName))
        values.append(escape(record.musicKey ?? "—"))
        values.append(record.tempoBPM.map { String(format: "%.1f", $0) } ?? "—")
        values.append(escape(record.leadPart ?? "—"))
        values.append(record.integratedLUFS.map { String(format: "%.1f", $0) } ?? "—")
        values.append(String(format: "%.1f", record.truePeakDb))
        values.append(record.stereoCorrelation.map { String(format: "%.2f", $0) } ?? "—")
        values.append(String(format: "%.1f", record.lowEnergyPercent))
        values.append(String(format: "%.0f", record.artifactHiss ?? 0))
        values.append(String(format: "%.0f", record.artifactShimmer ?? 0))
        values.append(String(format: "%.0f", record.artifactSpectralHole ?? 0))
        values.append(String(format: "%.0f", record.artifactTransientSmear ?? 0))
        values.append(String(format: "%.0f", record.artifactOverall ?? 0))
        let checks = record.failedChecks + record.reviewChecks
        if checks.isEmpty {
            values.append("—")
        } else {
            let pills = checks.map { check -> String in
                "<span class=\"pill\">\(escape(check))</span>"
            }
            values.append(pills.joined())
        }
        if record.issueIntervals.isEmpty {
            values.append("—")
        } else {
            let intervals = record.issueIntervals.prefix(4).map { interval -> String in
                String(format: "%.1f-%.1fs %@", interval.startTime, interval.endTime, interval.issue)
            }
            values.append(escape(intervals.joined(separator: "；")))
        }
        values.append(escape(record.error ?? ""))
        return "<tr><td>" + values.joined(separator: "</td><td>") + "</td></tr>"
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
