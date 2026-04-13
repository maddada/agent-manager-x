# Changelog

All notable changes to Agent Manager X will be documented in this file.

## 2.1 - 2026-04-13

### Added

- Added a configurable mini viewer expand delay control in Settings so you can tune how quickly the floating sidebar opens on hover.
- Added overflow protection for active VSmux mini viewer sessions so important sessions stay visible even when recent-session filtering or max-session limits would normally push them out.

### Fixed

- Improved bundled mini viewer hover expansion with a more forgiving hover strip and delayed expansion behavior, especially when the viewer is collapsed on the right edge.

## 2.0 - 2026-04-12

### Added

- Added a VSmux-backed session mode alongside process-based detection, with clearer session source labels in the dashboard.
- Added mini viewer monitor targeting, session count limits, and a smarter recent-session filter that can keep one session visible per project.
- Added a bundled mini viewer resource fallback so the floating viewer can still materialize its Swift source and icons outside the development tree.

### Changed

- Refined mini viewer ordering so sessions stay consistently sorted and easier to scan.
- Updated mini viewer and dashboard status styling so active sessions are easier to distinguish and completed sessions are labeled as done.
- Reorganized settings so mini viewer options are easier to find.

## 1.6 - 2026-03-13

- Improved mini viewer hover detection and sidebar positioning.

## 1.5 - 2026-03-13

- Added release packaging for separate Apple Silicon and Intel DMGs.
