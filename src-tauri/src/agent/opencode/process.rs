//! OpenCode process detection

use crate::agent::AgentProcess;
use crate::process::system::{get_system, refresh_processes};

/// Find running opencode processes
pub fn find_opencode_processes() -> Vec<AgentProcess> {
    let mut system_guard = get_system();
    let system = system_guard.as_mut().expect("System should be initialized");

    // Refresh process list
    refresh_processes(system);

    let mut processes = Vec::new();

    for (pid, process) in system.processes() {
        let name = process.name().to_string_lossy().to_lowercase();

        if name == "opencode" {
            let cpu = process.cpu_usage();
            let cwd = process.cwd().map(|p| p.to_path_buf());
            log::debug!(
                "OpenCode process: pid={}, cpu={:.1}%, cwd={:?}",
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

    log::debug!("Found {} opencode processes", processes.len());
    processes
}
