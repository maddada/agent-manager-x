# Agent Manager X 2.6

## Added

- Added Sparkle update support with signed appcasts, automatic checks, and a manual "Check for Updates..." app command.
- Added an App Updates section in Settings that shows the current version, update status, last check time, and automatic check toggle.
- Added zmux as a live mux session source alongside vsmux, with source-aware session identities and direct zmux focus requests.

## Changed

- Refined mini viewer sizing, hover tracking, and bundled resources so the floating sidebar stays aligned to visible session content.
- Reduced redundant mini viewer payload writes and git diff refreshes to avoid unnecessary UI churn.
- Updated mux session labels across the dashboard and settings to reflect merged vsmux / zmux support.
