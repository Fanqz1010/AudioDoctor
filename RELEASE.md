# Release Notes

## v0.4.2-beta.2 - 2026-11-09

### Added

- Music structure analysis for single files:
  - Key and mode estimation with tonic, candidates, confidence, and 12-pitch-class distribution.
  - Tempo estimation with BPM, beat interval, estimated beat count, onset density, and a conservative meter hint.
  - Arrangement role estimation for lead, accompaniment, bass, drums/percussion, pad, and keys/guitar-like layers.
- Music structure fields in batch CSV and HTML reports.
- Batch summary cards for key distribution, median BPM, and common lead-part estimates.
- Content optimization workspace now shows a compact music-structure reference.
- CI checks for tonality, tempo, arrangement JSON, and batch report columns.

### Notes

- Tonality, tempo, meter, and instrumentation are heuristic estimates on the mixed stereo/master signal. They are not source separation, automatic transcription, or a guarantee of real instrument identity.

## v0.4.0 - 2026-11-05

### Added

- Three-workspace product structure: AI artifact precision repair, batch badcase annotation, and content-aware optimization.
- Seven transparent artifact indicators: hiss, shimmer/metallic feeling, spectral holes, thinness, phase instability, transient smear, and stereo anomaly.
- Time-based badcase localization with start/end seconds, issue type, severity, evidence, confidence, and suggested fix.
- Batch HTML summary reports with grade distribution, concentrated issue ranking, worst-file priority list, and batch recommendations.
- Content presets for general music, Suno vocal, Suno pop, electronic, cinematic, and podcast material.
- Low-frequency mono stabilization and envelope-following transient recovery.
- More detailed CSV columns for all artifact dimensions and localized issues.
- Regression coverage for analysis, repair, 5.1/AmbiX conversion, recursive batches, resume-friendly skipping, and a 1,000-file batch.

### Changed

- The high-frequency exciter is attenuated when repaired output still has excessive high-band noise.
- Single-file analysis now shows a dedicated seven-dimension artifact dashboard and time-axis badcase list.
- Batch reports preserve the original annotation metrics while adding artifact diagnostics and aggregate conclusions.

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
