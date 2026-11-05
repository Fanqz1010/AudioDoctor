# Lightweight audio analyzer

`audio_analyzer.py` is a small companion CLI for quick metadata and level checks.

## Usage

```bash
# WAV works with no third-party dependency
python3 scripts/audio_analyzer.py input.wav

# Analyze every supported audio file in a folder, recursively
python3 scripts/audio_analyzer.py /path/to/folder

# Metadata only, skip peak/RMS calculation
python3 scripts/audio_analyzer.py --no-stats input.wav
```

Output includes file size, format, codec, sample rate, channel count, bit depth, frame count, duration, sample peak, RMS level, and mean absolute value.

## Optional formats

WAV is handled by Python's standard library. To analyze MP3, FLAC, OGG, OPUS, AIFF, and other formats supported by your local libsndfile build:

```bash
python3 -m pip install soundfile
```

This script is intentionally lightweight and does not replace the main Audio Doctor app. The native app additionally provides LUFS, true peak, clipping, phase correlation, stereo width, spectral balance, repair, and spatial-format conversion.
