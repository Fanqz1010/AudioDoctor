# Release Notes

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
