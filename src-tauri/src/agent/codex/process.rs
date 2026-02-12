//! Codex process detection functionality.

use crate::agent::AgentProcess;
use crate::process::system::{get_system, refresh_processes};
use std::path::{Path, PathBuf};
use std::process::Command;

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
        let is_app_server = cmd
            .get(1)
            .map(|arg| arg.to_string_lossy().eq_ignore_ascii_case("app-server"))
            .unwrap_or(false);

        if is_codex && !is_app_server {
            let cpu = process.cpu_usage();
            let cwd = process.cwd().map(|p| p.to_path_buf());
            let data_home = extract_env_var(process.environ(), "CODEX_HOME").map(PathBuf::from);
            let active_session_file = find_open_session_file(pid.as_u32(), data_home.as_deref());
            log::debug!(
                "Codex process: pid={}, cpu={:.1}%, mem={}MB, cwd={:?}, data_home={:?}, active_session_file={:?}",
                pid.as_u32(),
                cpu,
                process.memory() / 1024 / 1024,
                cwd,
                data_home,
                active_session_file
            );
            processes.push(AgentProcess {
                pid: pid.as_u32(),
                cpu_usage: cpu,
                memory_bytes: process.memory(),
                cwd,
                data_home,
                active_session_file,
            });
        }
        if is_codex && is_app_server {
            log::debug!(
                "Skipping Codex app-server process: pid={}, cmd={:?}",
                pid.as_u32(),
                cmd
            );
        }
    }

    log::debug!("Found {} codex processes", processes.len());
    processes
}

fn extract_env_var(environ: &[std::ffi::OsString], key: &str) -> Option<String> {
    let prefix = format!("{}=", key);
    environ.iter().find_map(|entry| {
        let text = entry.to_string_lossy();
        text.strip_prefix(&prefix)
            .filter(|value| !value.is_empty())
            .map(|value| value.to_string())
    })
}

fn find_open_session_file(pid: u32, data_home: Option<&Path>) -> Option<PathBuf> {
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
        if !path_str.ends_with(".jsonl") || !path_str.contains("/sessions/") {
            continue;
        }
        let path = PathBuf::from(path_str);
        if let Some(home) = data_home {
            if !path.starts_with(home) {
                continue;
            }
        }
        candidates.push(path);
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
