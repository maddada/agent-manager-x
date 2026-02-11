//! Main session discovery and aggregation logic.

use log::{debug, info, trace, warn};
use once_cell::sync::Lazy;
use std::collections::{HashMap, HashSet};
use std::path::PathBuf;
use std::sync::Mutex;

use crate::agent::AgentProcess;
use crate::session::model::{AgentType, Session, SessionStatus, SessionsResponse};
use crate::session::status_sort_priority;

use super::jsonl_files::{find_session_for_process, get_recently_active_jsonl_files};
use super::path_conversion::{convert_dir_name_to_path, convert_path_to_dir_name};

/// Track previous status for each session to detect transitions
static PREVIOUS_STATUS: Lazy<Mutex<HashMap<String, SessionStatus>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));

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

    if cwd_to_processes.is_empty() {
        info!(
            "No processes with cwd found for {:?}, skipping session scan",
            agent_type
        );
        return sessions;
    }

    // Build candidate project directory names from active process CWDs.
    // This avoids scanning every project folder on each poll cycle.
    let mut candidate_projects: HashMap<String, Vec<&AgentProcess>> = HashMap::new();
    for (cwd, process_group) in &cwd_to_processes {
        let exact_dir_name = convert_path_to_dir_name(cwd);
        candidate_projects
            .entry(exact_dir_name.clone())
            .or_default()
            .extend(process_group.iter().copied());

        // Compatibility fallback for legacy names where "_" was persisted as "-"
        let normalized_dir_name = exact_dir_name.replace('_', "-");
        if normalized_dir_name != exact_dir_name {
            candidate_projects
                .entry(normalized_dir_name)
                .or_default()
                .extend(process_group.iter().copied());
        }
    }
    debug!(
        "Built {} candidate project directories from {} cwd values",
        candidate_projects.len(),
        cwd_to_processes.len()
    );

    let claude_dirs = get_claude_projects_dirs();
    debug!("Claude project directories to scan: {:?}", claude_dirs);
    if claude_dirs.is_empty() {
        warn!("No Claude home directory found, skipping session scan");
        return sessions;
    }

    let mut found_existing_dir = false;
    let mut checked_project_count = 0usize;

    // For each Claude projects directory (default + optional profile dirs)
    for claude_dir in claude_dirs {
        if !claude_dir.exists() {
            debug!(
                "Claude projects directory does not exist, skipping: {:?}",
                claude_dir
            );
            continue;
        }
        found_existing_dir = true;

        for (dir_name, matching_processes) in &candidate_projects {
            let path = claude_dir.join(dir_name);
            if !path.is_dir() {
                trace!(
                    "Candidate project directory not found in {:?}: {}",
                    claude_dir, dir_name
                );
                continue;
            }

            checked_project_count += 1;

            let project_path = convert_dir_name_to_path(dir_name);
            debug!("Checking project: {} -> {}", dir_name, project_path);

            // Find all JSONL files that were recently modified (within last 30 seconds)
            // These are likely the active sessions
            let jsonl_files = get_recently_active_jsonl_files(&path);
            debug!(
                "Found {} JSONL files for project {}",
                jsonl_files.len(),
                project_path
            );

            // Match processes to JSONL files
            for (index, process) in matching_processes.iter().enumerate() {
                debug!(
                    "Matching process pid={} to JSONL file index {}",
                    process.pid, index
                );
                // Use actual CWD from process instead of reconstructed project_path
                let actual_path = process
                    .cwd
                    .as_ref()
                    .map(|p| p.to_string_lossy().to_string())
                    .unwrap_or_else(|| project_path.clone());
                if let Some(session) = find_session_for_process(
                    &jsonl_files,
                    &path,
                    &actual_path,
                    process,
                    index,
                    agent_type.clone(),
                ) {
                    // Track status transitions
                    let mut prev_status_map =
                        PREVIOUS_STATUS.lock().unwrap_or_else(|e| e.into_inner());
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
                        session.id,
                        session.project_name,
                        session.status,
                        session.pid,
                        session.cpu_usage
                    );
                    sessions.push(session);
                } else {
                    warn!(
                        "Failed to create session for process pid={} in project {}",
                        process.pid, project_path
                    );
                }
            }
        }
    }

    if !found_existing_dir {
        warn!("No Claude project directories found. Checked paths for default and profile setups.");
    } else if checked_project_count == 0 {
        debug!("No candidate project directories were found for active processes");
    }

    let original_count = sessions.len();
    let sessions = dedupe_sessions_by_pid(sessions);
    if sessions.len() != original_count {
        info!(
            "Deduplicated sessions by pid: {} -> {} (removed {})",
            original_count,
            sessions.len(),
            original_count.saturating_sub(sessions.len())
        );
    }

    info!(
        "=== Session scan complete for {:?}: {} total ===",
        agent_type,
        sessions.len()
    );

    sessions
}

fn get_claude_projects_dirs() -> Vec<PathBuf> {
    let Some(home) = dirs::home_dir() else {
        return Vec::new();
    };

    // Keep the legacy default location first, then profile-specific locations.
    let mut dirs = vec![home.join(".claude").join("projects")];

    for profile_root in [
        home.join(".claude-profiles").join("work"),
        home.join(".claude-profiles").join("personal"),
    ] {
        dirs.push(resolve_profile_projects_dir(profile_root));
    }

    dedupe_paths(dirs)
}

fn resolve_profile_projects_dir(profile_root: PathBuf) -> PathBuf {
    let projects_dir = profile_root.join("projects");
    if projects_dir.exists() {
        projects_dir
    } else {
        profile_root
    }
}

fn dedupe_paths(paths: Vec<PathBuf>) -> Vec<PathBuf> {
    let mut seen = HashSet::new();
    paths
        .into_iter()
        .filter(|path| seen.insert(path.clone()))
        .collect()
}

fn dedupe_sessions_by_pid(sessions: Vec<Session>) -> Vec<Session> {
    let mut best_by_pid: HashMap<u32, Session> = HashMap::new();

    for session in sessions {
        match best_by_pid.get_mut(&session.pid) {
            None => {
                best_by_pid.insert(session.pid, session);
            }
            Some(existing) => {
                if is_better_session(&session, existing) {
                    *existing = session;
                }
            }
        }
    }

    best_by_pid.into_values().collect()
}

fn is_better_session(candidate: &Session, current: &Session) -> bool {
    let candidate_priority = status_sort_priority(&candidate.status);
    let current_priority = status_sort_priority(&current.status);
    if candidate_priority != current_priority {
        return candidate_priority < current_priority;
    }

    if candidate.last_activity_at != current.last_activity_at {
        return candidate.last_activity_at > current.last_activity_at;
    }

    match (
        candidate.last_message.is_some(),
        current.last_message.is_some(),
    ) {
        (true, false) => true,
        (false, true) => false,
        _ => candidate.id > current.id,
    }
}
