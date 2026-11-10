import SwiftUI

enum WorkbenchCategory: String, CaseIterable, Identifiable {
    case content
    case structure
    case quality
    case timeline
    case conclusion

    var id: String { rawValue }

    var title: String {
        switch self {
        case .content: return "内容判断"
        case .structure: return "音乐结构"
        case .quality: return "技术质量"
        case .timeline: return "时间定位"
        case .conclusion: return "标确切认"
        }
    }

    var shortTitle: String {
        switch self {
        case .content: return "内容"
        case .structure: return "结构"
        case .quality: return "质量"
        case .timeline: return "定位"
        case .conclusion: return "确认"
        }
    }

    var subtitle: String {
        switch self {
        case .content: return "先判断能不能按音乐标注"
        case .structure: return "调性、节拍、配器、和弦"
        case .quality: return "响度、失真、相位、伪影"
        case .timeline: return "把问题落到秒数区间"
        case .conclusion: return "生成人工可复核结论"
        }
    }

    var step: String {
        switch self {
        case .content: return "01"
        case .structure: return "02"
        case .quality: return "03"
        case .timeline: return "04"
        case .conclusion: return "05"
        }
    }

    var systemImage: String {
        switch self {
        case .content: return "music.note.tv"
        case .structure: return "music.quarternote.3"
        case .quality: return "waveform.path.ecg"
        case .timeline: return "timer"
        case .conclusion: return "checkmark.seal"
        }
    }

    var color: Color {
        switch self {
        case .content: return Color(red: 0.32, green: 0.42, blue: 0.96)
        case .structure: return Color(red: 0.75, green: 0.28, blue: 0.72)
        case .quality: return Color(red: 0.10, green: 0.58, blue: 0.54)
        case .timeline: return Color(red: 0.85, green: 0.47, blue: 0.11)
        case .conclusion: return Color(red: 0.20, green: 0.62, blue: 0.29)
        }
    }
}

enum RepairCategory: String, CaseIterable, Identifiable {
    case overview
    case plan
    case spatial
    case result

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "修复总览"
        case .plan: return "修复方案"
        case .spatial: return "格式与空间"
        case .result: return "结果确认"
        }
    }

    var emoji: String {
        switch self {
        case .overview: return "🎧"
        case .plan: return "🩺"
        case .spatial: return "🌈"
        case .result: return "✨"
        }
    }

    var subtitle: String {
        switch self {
        case .overview: return "先看诊断，再动手"
        case .plan: return "按问题逐项修"
        case .spatial: return "声道与导出格式"
        case .result: return "前后对比确认"
        }
    }

    var color: Color {
        switch self {
        case .overview: return Color(red: 0.95, green: 0.42, blue: 0.48)
        case .plan: return Color(red: 0.31, green: 0.72, blue: 0.62)
        case .spatial: return Color(red: 0.38, green: 0.55, blue: 0.96)
        case .result: return Color(red: 0.90, green: 0.57, blue: 0.22)
        }
    }
}

struct WorkbenchSectionHeader: View {
    let category: WorkbenchCategory

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(category.color.opacity(0.14))
                    .frame(width: 48, height: 48)
                Image(systemName: category.systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(category.color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("\(category.step) · \(category.title)")
                    .font(.title3.weight(.semibold))
                Text(category.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
    }
}

struct WorkbenchCard<Content: View>: View {
    let title: String
    let caption: String
    let accent: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(caption).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Capsule()
                    .fill(accent.opacity(0.18))
                    .frame(width: 44, height: 5)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16)
                .fill(accent.opacity(0.22))
                .frame(width: 5)
                .padding(.vertical, 14)
        }
    }
}

struct CategoryPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(color.opacity(0.13), in: Capsule())
            .foregroundStyle(color)
    }
}

struct WorkbenchEmptyState: View {
    let title: String
    let subtitle: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.10))
                    .frame(width: 92, height: 92)
                Image(systemName: "waveform")
                    .font(.system(size: 34, weight:.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            VStack(spacing: 5) {
                Text(title).font(.title3.weight(.semibold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .frame(minWidth: 120)
                }
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
}
