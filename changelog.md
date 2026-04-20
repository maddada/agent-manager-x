# Changelog

All notable changes to Agent Manager X will be documented in this file.

## 2.4 - 2026-04-20

### Added

- Added VSmux workspace favicon propagation so project icon data can travel from workspace snapshots into session records and mini viewer payloads.
- Added project icon rendering to collapsed mini viewer project headers, with a deterministic folder-color fallback when no icon is available.

### Changed

- Refined the collapsed mini viewer header treatment so project identity stays visible before the full detail header fades in.

## 2.3 - 2026-04-19

### Added

- Added support for per-session VSmux project metadata so sessions can keep their own resolved project name and path instead of inheriting only the workspace fallback.

### Changed

- Refined the mini viewer's expand and collapse choreography so geometry and detail fades transition more smoothly.
- Kept the floating icon visible during left-side expansion and softened collapsed status indicators so the compact mini viewer is easier to scan without feeling visually harsh.

### Fixed

- Fixed mini viewer overflow protection and ordering to use stable render identities for sessions, preventing VSmux entries from colliding when multiple sessions share a project.

## 2.2 - 2026-04-17

### Added

- Added a mini viewer option to keep the whole expanded card hoverable after opening, making the floating panel easier to interact with.
- Added a configurable mini viewer collapse delay control in Settings for finer control over how quickly the sidebar closes after the pointer leaves.

### Changed

- Updated the menu bar count to show only active sessions instead of including idle ones.
- Filtered out blank Claude sessions rooted at `/` from the mini viewer so throwaway new-session placeholders do not clutter the floating view.

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
