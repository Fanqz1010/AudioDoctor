# GitHub 开源方案调研与合成思路

## 结论

没有找到一个完全等价的轻量 Mac 桌面应用，同时覆盖「音频体检 + 相位检测 + 声道转换 + 响度测量 + AI 音感修复」。因此第一版 Audio Doctor 将多个开源项目验证过的方向合成为一个原生 Mac app：

- ITU BS.1770 / EBU R128 响度测量
- 真峰与削波检测
- 相位相关性与 mid/side 宽度
- 频段能量分析
- 参考曲频响匹配
- 高频噪声抑制
- 轻度谐波激励
- 响度标准化与真峰限制

v0.2 继续加入两类空间音频转换：

- **立体声 → 5.1 WAV/AIFF**：输出 `L、R、C、LFE、Ls、Rs`。
- **立体声 → 一阶 AmbiX**：输出 `W、Y、Z、X`，采用 ACN 排序与 SN3D 归一化。

## 参考项目

| 项目 | 方向 | 对 Audio Doctor 的启发 |
|---|---|---|
| [Matchering](https://github.com/sergree/matchering) | 参考曲匹配、自动母带 | 使用参考曲的频响、响度、立体声宽度思路；Audio Doctor 实现了更保守的分段频响匹配 |
| [pyloudnorm](https://github.com/csteinmetz1/pyloudnorm) | Python LUFS 测量 | K-weighting 和门限积分响度算法 |
| [iver56/loudness](https://github.com/iver56/loudness) | 快速 BS.1770 响度库 | 确认离线 LUFS 测量可稳定实现 |
| [ebu-norm-tools](https://github.com/chmaha/ebu-norm-tools) | 批量 LUFS / True Peak 分析 | 批处理和报告指标设计 |
| [tonalux-analyzer](https://github.com/Exenye/tonalux-analyzer) | 浏览器音频分析器 | LUFS、True Peak、立体声、频谱的一站式展示 |
| [sonora](https://github.com/Px228-Da-Da/sonora) | 桌面实时音频计量 | goniometer 和相位相关性计量 |
| [sound-gambit](https://github.com/x42/sound-gambit) | 文件级峰值限制 | 文件离线处理和真峰限制思路 |
| [rack4master-reference](https://github.com/rack4master/rack4master-reference) | 频响参考匹配 | 频响匹配 UI 与处理链组织 |
| [noisyloop/mastering](https://github.com/noisyloop/mastering) | 本地母带套件 | 本地处理、参考匹配、频谱和立体声视图组合 |
| [versatile_audio_super_resolution](https://github.com/haoheliu/versatile_audio_super_resolution) | AI 音频超分 | 适合未来作为可选重模型，不适合第一版轻量 app 强依赖 |
| [Awesome-AI-Audio-Enhancement](https://github.com/ishandutta2007/Awesome-AI-Audio-Enhancement) | AI 音频修复项目清单 | 用于后续选择去噪、修复、源分离模型 |

## 空间音频与环绕声开源调研

| 项目 / 方案 | 方向 | 对 Audio Doctor v0.2 的启发 |
|---|---|---|
| [qutschwalze/Upmixer](https://github.com/qutschwalze/Upmixer) | macOS VST3/AU 立体声转 5.1/7.1 实时插件 | 确认了宽度、深度、中心分离度、LFE 管理和每声道表头是常用控制项；Audio Doctor 第一版先做离线一键转换，保留更保守的默认值 |
| [GWBasic/soft_matrix](https://github.com/GWBasic/soft_matrix) | Rust 命令行立体声转 5.1 | 说明相位关系和声像位置可以用于环绕声导向；其逐样本 FFT 方案较重，Audio Doctor 先用 mid/side 与带通做轻量实现 |
| [itsalic/StereoToSurroundUpmixer](https://github.com/itsalic/StereoToSurroundUpmixer) | 自适应立体声转 5.1 VST | 验证环绕声道通常需要限制进入后方扬声器的频带与能量 |
| [EmreNurbeyler/Upmichsen](https://github.com/EmreNurbeyler/Upmichsen) | 基于 Pro Logic II 思路的立体声转 5.1 | 提供矩阵解码与 Hilbert 相位扩展参考；Audio Doctor 未复制其算法，而使用可解释的 mid/side 矩阵 |
| [sweetspotsoundsystem/upmix-rt](https://github.com/sweetspotsoundsystem/upmix-rt) | MIT 实时立体声转多声道 / 一阶 Ambisonics | 其 W/Y 保留原始立体声、LFE 从 W 低通取值、扩散内容进入 surrounds 的设计很有参考价值；Audio Doctor 用保守近似实现 |
| [tu-studio/IEMPluginSuite](https://github.com/tu-studio/IEMPluginSuite) | Ambisonics 编码、旋转、解码、耳机渲染完整插件套件 | StereoEncoder/Decoder 的思路支持 ACN/SN3D；适合未来作为外部链路或对齐测试基准 |
| [leomccormack/SPARTA](https://github.com/leomccormack/SPARTA) | 高阶 Ambisonics 编码 / 解码 / 双耳渲染 | 提供 AmbiENC、AmbiDEC 等成熟实现；未来可对比一阶与高阶输出 |
| [videolan/libspatialaudio](https://github.com/videolan/libspatialaudio) | C++ HOA / 对象 / 扬声器 / 双耳渲染库 | 明确 ACN/SN3D、ADM/IAMF 等生态；说明 AmbiX 更适合作为开源空间交换层 |
| [VoidXH/Cavern](https://github.com/VoidXH/Cavern) | 对象音频、Dolby Atmos 渲染、房间校正 | 说明开源生态可处理 Atmos 渲染/解码，但正式 Atmos 母版生产仍涉及专用格式与授权链路，不适合在 v0.2 直接承诺 |
| [libambix 格式说明](https://iem-projects.github.io/ambix/apiref/format.html) | AmbiX / Ambisonics 文件布局 | 明确标准布局为 SN3D/ACN；Audio Doctor 的 4 声道顺序采用 `W、Y、Z、X` |

### v0.2 实现边界

1. **5.1 不是“魔法分离”**：它不会识别人声、鼓、混响等分轨，只用 mid/side、滤波、延迟和电平控制生成保守环绕版本。
2. **AmbiX 不是 Dolby Atmos**：AmbiX 是开放的空间音频表示；Atmos 通常需要对象/床 metadata、ADM BWF 或专用母版格式，以及授权工具链。
3. **先修复，再空间化**：处理顺序改为「读取 → 修复/响度标准化 → 声道/空间转换 → 导出」，避免把 AmbiX 分量误送进按普通扬声器设计的修复链。
4. **多声道输出安全**：4/6 声道输出加入声道布局，峰值控制在约 `-1 dB` 内。
5. **许可边界**：以上项目只作为算法和产品设计参考，Audio Doctor 当前没有复制 GPL/AGPL 代码；如未来直接集成，需要重新评估许可证。

## 为什么第一版不直接内置 AudioSR / DeepFilterNet 类模型

- 模型体积大，安装复杂，容易把轻量工具变成依赖地狱。
- 生成式超分会“发明”高频细节，有时会进一步改变 Suno 音色。
- 修复效果强依赖输入质量，不适合作为默认必选步骤。
- 更稳妥的路线是：先做可解释、可控的确定性处理，再把 AI 模型作为可选开关。

## 后续可选增强

1. **神经网络去噪 / 超分**：作为可选模型包，用户显式开启。
2. **频谱图和相位示波器**：帮助定位问题时间点。
3. **批量处理队列**：适合一次处理整张专辑或多版 Suno 输出。
4. **A/B 对比播放器**：原始/处理后快速切换。
5. **采样率和抖动控制**：输出到不同分发格式。
6. **MP3 / AAC 导出**：需要引入编码器或系统导出流程。
