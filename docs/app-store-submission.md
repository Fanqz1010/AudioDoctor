# Audio Doctor Mac App Store 提审准备

## 当前状态

仓库已准备 v0.5.0 的 macOS App 打包脚本、App Sandbox entitlements、Info.plist 模板和版本校验脚本。能否真正提交由 Apple 开发者账号、证书和 App Store Connect 记录决定。

## 提审前必须补齐

1. Apple Developer Program 已付费，并拥有 Team ID。
2. 创建 `com.fanqianzi.audiodoctor` 的 Mac App ID。
3. 创建 Mac App Store provisioning profile。
4. 安装 `3rd Party Mac Developer Application` 证书。
5. 在 App Store Connect 创建 macOS App 记录、截图、描述、关键词、隐私政策。
   - 可复用 `docs/app-store-metadata-zh.md` 的应用描述、关键词和审核备注。
   - 隐私政策可先部署 `docs/privacy-policy-zh.md`，需要一个可公开访问的 URL。
6. 明确商业模式：
   - 免费版本：可先提交基础分析与标注功能。
   - 付费买断 / 订阅：需要 App 内购买配置和恢复购买能力。
7. App Store 版建议关闭“内测码导出”表达，避免审核员误解功能不可用；内测版继续留在 GitHub Release。

## 打包命令

```bash
APP_NAME="Audio Doctor" \
SIGNING_IDENTITY="3rd Party Mac Developer Application: YOUR NAME (TEAM_ID)" \
PROFILE="/path/to/AudioDoctor.provisionprofile" \
./scripts/package_macos.sh
```

验证：

```bash
./scripts/validate_appstore.sh "build/package/Audio Doctor.app"
```

提交前还需要通过 Xcode Organizer、`xcrun altool` 或 Transporter 上传。当前机器只有 Command Line Tools，没有完整 Xcode，也没有有效 Apple 签名证书，因此无法在本机完成 App Store Connect 上传。

## 审核注意

- 核心价值是本地音频分析与标注辅助，不承诺“去除 AI 检测”。
- 和弦、调性、拍号、配器、转调、AI 感均为启发式分析，界面必须保留人工复核提示。
- AmbiX 是开源一阶空间音频格式，不称为 Dolby Atmos。
- 原始音频不会被覆盖，导出总是写入新文件。
