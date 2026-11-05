#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Lightweight audio metadata and level analyzer.

Features
--------
- Basic metadata: file size, format, codec, sample rate, channels, bit depth,
  frame count, and duration.
- Optional level statistics: sample peak, RMS level, and mean absolute value.
- WAV works with the Python standard library only.
- Other formats work when ``soundfile`` is installed.

Usage
-----
::

    python3 scripts/audio_analyzer.py input.wav
    python3 scripts/audio_analyzer.py /path/to/folder
    python3 scripts/audio_analyzer.py --no-stats input.wav

Optional dependencies
---------------------
``soundfile`` enables MP3, FLAC, OGG, OPUS, AIFF, and other libsndfile-backed
formats on your system::

    python3 -m pip install soundfile

The script does not require NumPy. When present, NumPy is only used to speed up
WAV sample conversion.
"""

from __future__ import annotations

import argparse
import array
import math
import sys
import wave
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

try:
    import numpy as np
    HAS_NUMPY = True
except ImportError:
    HAS_NUMPY = False

try:
    import soundfile as sf
    HAS_SOUNDFILE = True
except ImportError:
    HAS_SOUNDFILE = False

SUPPORTED_EXTS = {
    ".wav", ".mp3", ".flac", ".ogg", ".m4a", ".aac", ".wma", ".opus",
    ".aiff", ".aif",
}

BLOCK_FRAMES = 65536


@dataclass
class LevelStats:
    peak: float = 0.0
    sum_squares: float = 0.0
    sum_abs: float = 0.0
    count: int = 0

    def update(self, samples: Iterable[float]) -> None:
        count = 0
        sum_squares = 0.0
        sum_abs = 0.0
        peak = 0.0
        for value in samples:
            magnitude = abs(value)
            peak = max(peak, magnitude)
            sum_squares += value * value
            sum_abs += magnitude
            count += 1
        self.peak = max(self.peak, peak)
        self.sum_squares += sum_squares
        self.sum_abs += sum_abs
        self.count += count

    def as_dict(self) -> dict[str, str]:
        if self.count == 0:
            return {"统计": "无音频采样数据"}
        rms = math.sqrt(self.sum_squares / self.count)
        mean_abs = self.sum_abs / self.count

        def dbfs(value: float) -> str:
            return "-inf dBFS" if value <= 0 else f"{20 * math.log10(value):.2f} dBFS"

        return {
            "峰值": dbfs(self.peak),
            "RMS 电平": dbfs(rms),
            "平均绝对值": f"{mean_abs:.6f}",
        }


def channel_desc(n: int) -> str:
    if n == 1:
        return "单声道"
    if n == 2:
        return "立体声"
    return "多声道"


def _bytes_to_float(raw: bytes, samp_width: int):
    """Convert interleaved PCM WAV bytes to float samples in [-1, 1]."""
    if HAS_NUMPY:
        if samp_width == 1:
            return np.frombuffer(raw, dtype=np.uint8).astype(np.float32) / 128.0 - 1.0
        if samp_width == 2:
            return np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0
        if samp_width == 4:
            return np.frombuffer(raw, dtype="<i4").astype(np.float32) / 2147483648.0
    else:
        if samp_width == 1:
            return [(value - 128) / 128.0 for value in raw]
        if samp_width == 2:
            values = array.array("h")
            values.frombytes(raw)
            if sys.byteorder == "big":
                values.byteswap()
            return [value / 32768.0 for value in values]
        if samp_width == 4:
            values = array.array("i")
            values.frombytes(raw)
            if sys.byteorder == "big":
                values.byteswap()
            return [value / 2147483648.0 for value in values]

    if samp_width == 3:
        samples = []
        for offset in range(0, len(raw) - samp_width + 1, samp_width):
            chunk = raw[offset:offset + 3]
            value = int.from_bytes(chunk, byteorder="little", signed=True)
            samples.append(value / 8388608.0)
        return samples

    raise RuntimeError(f"暂不支持的 WAV 位深：{samp_width * 8} bit")


def analyze_wav(path: Path, include_stats: bool = True) -> dict[str, object]:
    with wave.open(str(path), "rb") as wf:
        channels = wf.getnchannels()
        samp_width = wf.getsampwidth()
        sample_rate = wf.getframerate()
        frames = wf.getnframes()
        comptype = wf.getcomptype()

        info: dict[str, object] = {
            "文件": str(path),
            "文件大小": f"{path.stat().st_size / 1024:.2f} KB",
            "格式": "WAV",
            "编码": "PCM 无压缩" if comptype == "NONE" else f"压缩（{comptype}）",
            "采样率": f"{sample_rate} Hz",
            "声道数": f"{channels}（{channel_desc(channels)}）",
            "位深": f"{samp_width * 8} bit",
            "总帧数": frames,
            "时长": f"{frames / sample_rate:.3f} 秒" if sample_rate else "未知",
        }
        if not include_stats:
            return info
        if comptype != "NONE":
            info["统计"] = "压缩 WAV 暂不支持统计计算"
            return info

        stats = LevelStats()
        remaining = frames
        while remaining:
            current = min(BLOCK_FRAMES, remaining)
            raw = wf.readframes(current)
            if not raw:
                break
            stats.update(_bytes_to_float(raw, samp_width))
            remaining -= current
        info.update(stats.as_dict())
        return info


def analyze_generic(path: Path, include_stats: bool = True) -> dict[str, object]:
    meta = sf.info(str(path))
    info: dict[str, object] = {
        "文件": str(path),
        "文件大小": f"{path.stat().st_size / 1024:.2f} KB",
        "格式": meta.format,
        "编码": meta.subtype,
        "采样率": f"{meta.samplerate} Hz",
        "声道数": f"{meta.channels}（{channel_desc(meta.channels)}）",
    }
    if meta.subtype:
        digits = "".join(ch for ch in meta.subtype if ch.isdigit())
        if digits:
            info["位深"] = f"{int(digits)} bit"
    info["总帧数"] = meta.frames
    info["时长"] = f"{meta.duration:.3f} 秒"

    if not include_stats:
        return info
    stats = LevelStats()
    for block in sf.blocks(str(path), dtype="float32", always_2d=True):
        stats.update(block.ravel())
    info.update(stats.as_dict())
    return info


def analyze_file(path: Path, include_stats: bool = True) -> dict[str, object]:
    if not path.is_file():
        raise FileNotFoundError(path)
    if path.suffix.lower() not in SUPPORTED_EXTS:
        raise RuntimeError(f"不支持的音频扩展名：{path.suffix}")
    if HAS_SOUNDFILE:
        return analyze_generic(path, include_stats)
    if path.suffix.lower() == ".wav":
        return analyze_wav(path, include_stats)
    raise RuntimeError(
        f"无法解析 {path.suffix} 格式：未安装 soundfile。"
        "可执行：python3 -m pip install soundfile"
    )


def print_result(info: dict[str, object]) -> None:
    for key, value in info.items():
        print(f"{key}: {value}")


def find_audio_files(folder: Path) -> list[Path]:
    return [path for path in sorted(folder.rglob("*")) if path.is_file() and path.suffix.lower() in SUPPORTED_EXTS]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="批量查看音频基础参数，WAV 无需第三方依赖。"
    )
    parser.add_argument("target", type=Path, help="音频文件或文件夹")
    parser.add_argument("--no-stats", action="store_true", help="只显示元数据，不计算电平统计")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    target = args.target
    if target.is_dir():
        files = find_audio_files(target)
        if not files:
            print(f"目录中未找到支持的音频文件：{target}")
            raise SystemExit(1)
        for index, path in enumerate(files, start=1):
            if index > 1:
                print()
            print(f"--- {path.name} ---")
            try:
                print_result(analyze_file(path, not args.no_stats))
            except Exception as exc:
                print(f"[错误] {exc}")
        return

    if target.is_file():
        try:
            print_result(analyze_file(target, not args.no_stats))
        except Exception as exc:
            print(f"[错误] {exc}")
            raise SystemExit(1)
        return

    print(f"路径不存在：{target}")
    raise SystemExit(1)


if __name__ == "__main__":
    main()
