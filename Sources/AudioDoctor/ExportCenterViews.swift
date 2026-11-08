import SwiftUI

struct ExportCenterView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                if model.isBetaUnlocked {
                    unlockedContent
                } else {
                    lockedContent
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("内测导出中心")
                    .font(.title2.weight(.semibold))
                Text("版本 \(BetaAccess.buildVersion) · 有效期至 2026-12-31")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
    }

    private var lockedContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("为什么现在需要内测码？") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("分析、定位和批量体检报告可以继续使用；音频修复导出涉及完整处理链路和输出质量，目前只对早期用户开放。")
                    Text("内测期间欢迎免费试用，并反馈沙声、低频、瞬态、人声自然度和导出体验。")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            GroupBox("输入内测码") {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("例如：SUNO-BETA-2026", text: $model.betaCodeInput)
                        .textFieldStyle(.roundedBorder)
                    if let error = model.betaUnlockError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    HStack {
                        Button {
                            unlock()
                        } label: {
                            Label("开启内测导出", systemImage: "key")
                                .frame(maxWidth: .infinity)
                        }
                        .controlSize(.large)
                        .disabled(model.betaCodeInput.isEmpty)
                        Button("稍后再说") {
                            dismiss()
                        }
                    }
                    Text("这是本地内测门槛，不是正式版权保护；商业版会替换为账号授权和订单系统。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var unlockedContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            DropZone(
                title: "拖入要导出的音频",
                subtitle: "支持 WAV / AIFF / M4A / MP3；也可以先关闭本窗口后在主界面拖入"
            ) { url in
                model.loadFile(url: url)
            }

            GroupBox("Suno 快速方案") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Button {
                            model.applySunoRecommendedSettings(vocalFocus: true)
                        } label: {
                            Label("人声为主", systemImage: "person.wave.2")
                                .frame(maxWidth: .infinity)
                        }
                        Button {
                            model.applySunoRecommendedSettings(vocalFocus: false)
                        } label: {
                            Label("流行歌曲", systemImage: "music.note")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    Text("推荐链路：高频伪影抑制 → 低频补偿 → 低频相位稳定 → 瞬态恢复 → -14 LUFS 标准化 → -1 dBTP 限制。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox("导出摘要") {
                VStack(alignment: .leading, spacing: 8) {
                    summaryRow("音频", model.inputURL?.lastPathComponent ?? "尚未导入")
                    summaryRow("内容预设", model.repair.preset.title)
                    summaryRow("声道", channelTitle)
                    summaryRow("格式", "\(model.outputFormat.uppercased()) / \(model.bitDepth)-bit")
                    summaryRow("目标响度", String(format: "%.1f LUFS", model.repair.targetLUFS))
                }
                .font(.caption)
            }

            GroupBox("导出后会生成两个文件") {
                VStack(alignment: .leading, spacing: 8) {
                    Label("修复后的音频：原始文件不会被覆盖", systemImage: "waveform")
                    Label("JSON 反馈报告：包含处理前后客观指标，方便发回给开发者", systemImage: "doc.text.magnifyingglass")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Button {
                model.processAndExport()
            } label: {
                Label(model.inputURL == nil ? "请先拖入音频" : "选择位置并导出", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(model.inputURL == nil || model.isWorking)

            if model.isWorking {
                ProgressView("正在处理音频…")
            }
            if let message = model.message {
                Label(message, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            GroupBox("内测用户反馈清单") {
                VStack(alignment: .leading, spacing: 6) {
                    feedbackItem("高频沙沙声是否减少？")
                    feedbackItem("低频是否更有身体感？")
                    feedbackItem("鼓点和人声边界是否更清楚？")
                    feedbackItem("整体音量是否稳定？")
                    feedbackItem("导出流程是否容易理解？")
                }
                .font(.caption)
            }
        }
    }

    private func unlock() {
        model.unlockBetaAccess()
        if model.isBetaUnlocked {
            model.errorMessage = nil
        }
    }

    private func summaryRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
    }

    private func feedbackItem(_ text: String) -> some View {
        Label(text, systemImage: "circle")
            .foregroundStyle(.secondary)
    }

    private var channelTitle: String {
        switch model.channelTarget {
        case "mono": return "立体声 → 单声道"
        case "stereo": return "单声道 → 立体声"
        case "surround51": return "立体声 → 5.1"
        case "ambix": return "立体声 → AmbiX"
        default: return "保持原声道"
        }
    }
}
