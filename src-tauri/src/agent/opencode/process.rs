//! OpenCode process detection

use crate::agent::AgentProcess;
use crate::process::system::{get_system, refresh_processes};
use std::path::PathBuf;
use std::process::Command;

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
            let active_session_file = find_open_opencode_session_file(pid.as_u32());
            log::debug!(
                "OpenCode process: pid={}, cpu={:.1}%, mem={}MB, cwd={:?}, active_session_file={:?}",
                pid.as_u32(),
                cpu,
                process.memory() / 1024 / 1024,
                cwd,
                active_session_file
            );
            processes.push(AgentProcess {
                pid: pid.as_u32(),
                cpu_usage: cpu,
                memory_bytes: process.memory(),
                cwd,
                data_home: None,
                active_session_file,
            });
        }
    }

    log::debug!("Found {} opencode processes", processes.len());
    processes
}

fn find_open_opencode_session_file(pid: u32) -> Option<PathBuf> {
    let output = Command::new("lsof")
        .arg("-Fn")
        .arg("-p")
        .arg(pid.to_string())
        .output()
        .ok()?;

    if !output.status.success() {
        return None;
    }

    let mut candidates = Vec::new();
    for line in String::from_utf8_lossy(&output.stdout).lines() {
        let Some(path_str) = line.strip_prefix('n') else {
            continue;
        };
        if !path_str.ends_with(".json") || !path_str.contains("/opencode/storage/session/") {
            continue;
        }
        candidates.push(PathBuf::from(path_str));
    }

    if candidates.is_empty() {
        return None;
    }

    candidates.sort_by(|a, b| {
        let a_mtime = a
            .metadata()
            .and_then(|m| m.modified())
            .ok()
            .unwrap_or(std::time::SystemTime::UNIX_EPOCH);
        let b_mtime = b
            .metadata()
            .and_then(|m| m.modified())
            .ok()
            .unwrap_or(std::time::SystemTime::UNIX_EPOCH);
        b_mtime.cmp(&a_mtime)
    });

    candidates.into_iter().next()
}
