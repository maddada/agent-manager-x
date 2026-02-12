//! Shared sysinfo::System instance for process monitoring.
//!
//! This module provides a single static System instance that is shared across
//! all process detection modules (Claude, OpenCode, Codex) to avoid code
//! duplication and reduce memory usage.

use std::sync::Mutex;
use std::time::{Duration, Instant};
use sysinfo::{ProcessRefreshKind, RefreshKind, System, UpdateKind};

/// Shared System instance for process monitoring.
/// Using a single instance avoids 3x memory usage from separate instances.
static SYSTEM: Mutex<Option<System>> = Mutex::new(None);
static LAST_PROCESS_REFRESH_AT: Mutex<Option<Instant>> = Mutex::new(None);

/// Avoid back-to-back full process refreshes when multiple detectors run in
/// the same polling cycle.
const MIN_PROCESS_REFRESH_INTERVAL: Duration = Duration::from_millis(750);

/// Get a mutable reference to the shared System instance.
/// Initializes the System on first access with full process refresh capabilities.
///
/// The caller must hold the returned MutexGuard for the duration of their
/// operations on the System.
///
/// # Example
/// ```ignore
/// let mut system_guard = get_system();
/// let system = system_guard.as_mut().unwrap();
/// // Use system for process operations
/// ```
pub fn get_system() -> std::sync::MutexGuard<'static, Option<System>> {
    let mut guard = SYSTEM.lock().unwrap_or_else(|e| e.into_inner());

    // Initialize system if not already done
    if guard.is_none() {
        log::debug!("Initializing shared System instance for process monitoring");
        *guard = Some(System::new_with_specifics(
            RefreshKind::new().with_processes(
                ProcessRefreshKind::new()
                    .with_cmd(UpdateKind::Always)
                    .with_cwd(UpdateKind::Always)
                    .with_cpu()
                    .with_memory(),
            ),
        ));
    }

    guard
}

/// Refresh the process list with full details.
/// Call this before iterating over processes to get up-to-date information.
pub fn refresh_processes(system: &mut System) {
    let should_refresh = {
        let mut last_refresh = LAST_PROCESS_REFRESH_AT
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        match *last_refresh {
            Some(previous) if previous.elapsed() < MIN_PROCESS_REFRESH_INTERVAL => false,
            _ => {
                *last_refresh = Some(Instant::now());
                true
            }
        }
    };

    if !should_refresh {
        log::trace!(
            "Skipping process refresh (last refresh < {:?})",
            MIN_PROCESS_REFRESH_INTERVAL
        );
        return;
    }

    system.refresh_processes_specifics(
        sysinfo::ProcessesToUpdate::All,
        ProcessRefreshKind::new()
            .with_cmd(UpdateKind::Always)
            .with_cwd(UpdateKind::Always)
            .with_cpu()
            .with_memory(),
    );
}
