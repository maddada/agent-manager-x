//! Main session discovery and aggregation logic.

use log::{debug, info, trace, warn};
use once_cell::sync::Lazy;
use std::collections::HashMap;
use std::fs;
use std::sync::Mutex;

use crate::agent::AgentProcess;
use crate::session::model::{AgentType, Session, SessionStatus, SessionsResponse};

use super::jsonl_files::{find_session_for_process, get_recently_active_jsonl_files};
use super::path_conversion::{convert_dir_name_to_path, convert_path_to_dir_name};

/// Track previous status for each session to detect transitions
static PREVIOUS_STATUS: Lazy<Mutex<HashMap<String, SessionStatus>>> = Lazy::new(|| Mutex::new(HashMap::new()));

/// Get all active Claude Code sessions (delegates to agent module)
pub fn get_sessions() -> SessionsResponse {
    crate::agent::get_all_sessions()
}

/// Internal function to get sessions for a specific agent type
/// Called by agent detectors (ClaudeDetector, OpenCodeDetector, etc.)
pub fn get_sessions_internal(processes: &[AgentProcess], agent_type: AgentType) -> Vec<Session> {
    info!("=== Getting sessions for {:?} ===", agent_type);
    debug!("Found {} processes total", processes.len());

    let mut sessions = Vec::new();

    // Build a map of cwd -> list of processes (multiple sessions can run in same folder)
    let mut cwd_to_processes: HashMap<String, Vec<&AgentProcess>> = HashMap::new();
    for process in processes {
        if let Some(cwd) = &process.cwd {
            let cwd_str = cwd.to_string_lossy().to_string();
            debug!("Mapping process pid={} to cwd={}", process.pid, cwd_str);
            cwd_to_processes.entry(cwd_str).or_default().push(process);
        } else {
            warn!("Process pid={} has no cwd, skipping", process.pid);
        }
    }

    // Scan ~/.claude/projects for session files
    let claude_dir = dirs::home_dir()
        .map(|h| h.join(".claude").join("projects"))
        .unwrap_or_default();

    debug!("Claude projects directory: {:?}", claude_dir);

    if !claude_dir.exists() {
        warn!("Claude projects directory does not exist: {:?}", claude_dir);
        return sessions;
    }

    // For each project directory
    if let Ok(entries) = fs::read_dir(&claude_dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if !path.is_dir() {
                continue;
            }

            // Convert directory name back to path
            let dir_name = path.file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("");

            let project_path = convert_dir_name_to_path(dir_name);
            debug!("Checking project: {} -> {}", dir_name, project_path);

            // Check if this project has active processes
            // First try exact match
            let matching_processes = if let Some(p) = cwd_to_processes.get(&project_path) {
                debug!("Project {} has {} active processes (exact match)", project_path, p.len());
                p
            } else {
                // Try to find a matching cwd by converting each cwd to a dir name and comparing
                let matching_cwd = cwd_to_processes.keys().find(|cwd| {
                    let cwd_as_dir = convert_path_to_dir_name(cwd);
                    if cwd_as_dir == dir_name {
                        return true;
                    }
                    // Also try normalized comparison (handle underscore/dash differences)
                    let normalized_cwd = cwd_as_dir.replace('_', "-").to_lowercase();
                    let normalized_dir = dir_name.replace('_', "-").to_lowercase();
                    if normalized_cwd == normalized_dir {
                        debug!("Matched via normalized comparison: {} vs {}", cwd_as_dir, dir_name);
                        return true;
                    }
                    false
                });

                match matching_cwd {
                    Some(cwd) => {
                        debug!("Project {} matched via reverse lookup to cwd {}", dir_name, cwd);
                        // Safe to unwrap since we just found this key exists
                        cwd_to_processes.get(cwd).unwrap()
                    }
                    None => {
                        trace!("Project {} has no active processes, skipping", project_path);
                        continue;
                    }
                }
            };

            // Find all JSONL files that were recently modified (within last 30 seconds)
            // These are likely the active sessions
            let jsonl_files = get_recently_active_jsonl_files(&path);
            debug!("Found {} JSONL files for project {}", jsonl_files.len(), project_path);

            // Match processes to JSONL files
            for (index, process) in matching_processes.iter().enumerate() {
                debug!("Matching process pid={} to JSONL file index {}", process.pid, index);
                // Use actual CWD from process instead of reconstructed project_path
                let actual_path = process.cwd
                    .as_ref()
                    .map(|p| p.to_string_lossy().to_string())
                    .unwrap_or_else(|| project_path.clone());
                if let Some(session) = find_session_for_process(&jsonl_files, &path, &actual_path, process, index, agent_type.clone()) {
                    // Track status transitions
                    let mut prev_status_map = PREVIOUS_STATUS.lock().unwrap_or_else(|e| e.into_inner());
                    let prev_status = prev_status_map.get(&session.id).cloned();

                    // Log status transition if it changed
                    if let Some(prev) = &prev_status {
                        if *prev != session.status {
                            warn!(
                                "STATUS TRANSITION: project={}, {:?} -> {:?}, cpu={:.1}%, file_age=?, last_msg_role={:?}",
                                session.project_name, prev, session.status, session.cpu_usage, session.last_message_role
                            );
                        }
                    }

                    // Update stored status
                    prev_status_map.insert(session.id.clone(), session.status.clone());
                    drop(prev_status_map);

                    info!(
                        "Session created: id={}, project={}, status={:?}, pid={}, cpu={:.1}%",
                        session.id, session.project_name, session.status, session.pid, session.cpu_usage
                    );
                    sessions.push(session);
                } else {
                    warn!("Failed to create session for process pid={} in project {}", process.pid, project_path);
                }
            }
        }
    }

    info!(
        "=== Session scan complete for {:?}: {} total ===",
        agent_type, sessions.len()
    );

    sessions
}
