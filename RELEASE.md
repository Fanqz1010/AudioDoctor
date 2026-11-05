# Release Notes

## v0.3.0 - 2026-11-05

### Added

- Separate single-file precision workspace and thousand-file batch workspace.
- Recursive batch scanning and sequential processing queue.
- Analyze-only batch mode with incremental CSV report writing.
- Batch repair/export mode with resume-friendly skip-existing behavior.
- Real-time batch progress, success/failure/skipped counters, and cancellation.
- Objective annotation dashboard with transparent thresholds and visual indicators.
- New metrics: channel balance, mono fold-down loss, spatial expansion index, and clipping percentage.
- Detailed Chinese annotation standards for loudness, true peak, clipping, dynamics, phase, mono compatibility, spatial data, band balance, hiss, and heuristic AI feel.
- CLI `batch` command.
- Validated with a recursive 1,000-file batch test.

## Repository update - 2026-11-05

### Added

- Lightweight Python companion CLI for metadata, peak, RMS level, and mean absolute value.
- Dependency-free WAV parsing, including 8/16/24/32-bit PCM and recursive folder analysis.
- Optional `soundfile` support for additional formats.

## v0.2.0 - 2026-11-05

### Added

- Stereo to 5.1 surround conversion with `L R C LFE Ls Rs` output.
- Stereo to first-order AmbiX conversion with `W Y Z X` ACN/SN3D output.
- Multi-channel WAV/AIFF export with channel layouts.
- CLI `convert` command for offline regression testing.
- Chinese user guide, open-source research notes, and GitHub Actions build workflow.

### Changed

- Processing order now repairs and normalizes the source before channel/spatial conversion.
- Spatial exports keep analysis metrics based on the repaired stereo source to avoid misleading AmbiX phase readings.

## v0.1.0 - 2026-11-04

### Added

- Drag-and-drop audio analysis.
- LUFS, true peak, clipping, RMS, crest factor, DC offset, phase, stereo width, and spectral balance reporting.
- De-hiss, fullness repair, reference matching, air/detail enhancement, loudness normalization, and true-peak limiting.
- Stereo/mono conversion and WAV/AIFF export.
