//! Codex process detection functionality.

use crate::agent::AgentProcess;
use crate::process::system::{get_system, refresh_processes};

/// Find running codex processes.
pub fn find_codex_processes() -> Vec<AgentProcess> {
    let mut system_guard = get_system();
    let system = system_guard.as_mut().expect("System should be initialized");

    refresh_processes(system);

    let mut processes = Vec::new();

    for (pid, process) in system.processes() {
        let cmd = process.cmd();

        // Check if this is a codex process
        let is_codex = if let Some(first_arg) = cmd.first() {
            let first_arg_str = first_arg.to_string_lossy().to_lowercase();
            first_arg_str == "codex" || first_arg_str.ends_with("/codex")
        } else {
            false
        };

        if is_codex {
            let cpu = process.cpu_usage();
            let cwd = process.cwd().map(|p| p.to_path_buf());
            log::debug!(
                "Codex process: pid={}, cpu={:.1}%, cwd={:?}",
                pid.as_u32(),
                cpu,
                cwd
            );
            processes.push(AgentProcess {
                pid: pid.as_u32(),
                cpu_usage: cpu,
                cwd,
            });
        }
    }

    log::debug!("Found {} codex processes", processes.len());
    processes
}
