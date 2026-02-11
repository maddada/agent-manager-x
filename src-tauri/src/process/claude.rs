use log::{debug, trace};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

use super::system::{get_system, refresh_processes};

/// Represents a running Claude Code process
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ClaudeProcess {
    pub pid: u32,
    pub cwd: Option<PathBuf>,
    pub cpu_usage: f32,
    pub memory: u64,
}

/// Find all running Claude Code processes on the system
/// Filters out sub-agent processes (whose parent is also a Claude process)
pub fn find_claude_processes() -> Vec<ClaudeProcess> {
    use std::collections::HashSet;
    use sysinfo::Pid;

    debug!("=== Starting process discovery ===");

    let mut system_guard = get_system();
    let system = system_guard.as_mut().expect("System should be initialized");

    // Refresh process list with full details
    refresh_processes(system);

    let total_processes = system.processes().len();
    trace!("Total system processes: {}", total_processes);

    // First pass: collect all Claude process PIDs
    let mut claude_pids: HashSet<Pid> = HashSet::new();
    for (pid, process) in system.processes() {
        let cmd = process.cmd();
        let is_claude = if let Some(first_arg) = cmd.first() {
            let first_arg_str = first_arg.to_string_lossy().to_lowercase();
            first_arg_str == "claude" || first_arg_str.ends_with("/claude")
        } else {
            false
        };
        if is_claude {
            claude_pids.insert(*pid);
        }
    }

    let mut processes = Vec::new();

    // Second pass: collect Claude processes, excluding sub-agents
    for (pid, process) in system.processes() {
        let cmd = process.cmd();
        let process_name = process.name().to_string_lossy();

        let is_claude = if let Some(first_arg) = cmd.first() {
            let first_arg_str = first_arg.to_string_lossy().to_lowercase();
            first_arg_str == "claude" || first_arg_str.ends_with("/claude")
        } else {
            false
        };

        // Exclude our own app
        let is_our_app = process_name.contains("agent-manager-x");

        if is_claude {
            let cwd = process.cwd().map(|p| p.to_path_buf());

            if is_our_app {
                trace!(
                    "Skipping our own app: pid={}, name={}",
                    pid.as_u32(),
                    process_name
                );
                continue;
            }

            // Check if parent is also a Claude process (indicates sub-agent)
            if let Some(parent_pid) = process.parent() {
                if claude_pids.contains(&parent_pid) {
                    debug!(
                        "Skipping sub-agent process: pid={}, parent_pid={}, cwd={:?}",
                        pid.as_u32(),
                        parent_pid.as_u32(),
                        cwd
                    );
                    continue;
                }

                // Check if parent is Zed's external agent (claude-code-acp)
                // These are auto-spawned by Zed and not user-initiated terminal sessions
                if let Some(parent_process) = system.process(parent_pid) {
                    let parent_cmd: String = parent_process
                        .cmd()
                        .iter()
                        .map(|s| s.to_string_lossy())
                        .collect::<Vec<_>>()
                        .join(" ");
                    if parent_cmd.contains("claude-code-acp") {
                        debug!(
                            "Skipping Zed external agent: pid={}, parent_pid={}, cwd={:?}",
                            pid.as_u32(),
                            parent_pid.as_u32(),
                            cwd
                        );
                        continue;
                    }
                }
            }

            debug!(
                "Found Claude process: pid={}, cwd={:?}, cpu={:.1}%, mem={}MB",
                pid.as_u32(),
                cwd,
                process.cpu_usage(),
                process.memory() / 1024 / 1024
            );

            processes.push(ClaudeProcess {
                pid: pid.as_u32(),
                cwd,
                cpu_usage: process.cpu_usage(),
                memory: process.memory(),
            });
        }
    }

    debug!(
        "Process discovery complete: found {} Claude processes (excluding sub-agents)",
        processes.len()
    );
    processes
}
