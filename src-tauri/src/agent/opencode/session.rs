//! OpenCode session loading and extraction

use super::builder::build_session;
use super::project::{find_latest_session_in_dir, load_projects};
use super::types::OpenCodeProject;
use crate::agent::AgentProcess;
use crate::session::Session;
use std::collections::HashMap;
use std::path::PathBuf;

/// Get OpenCode sessions from JSON files
pub fn get_opencode_sessions(processes: &[AgentProcess]) -> Vec<Session> {
    let mut sessions = Vec::new();

    // OpenCode data directory: ~/.local/share/opencode/storage/
    let storage_path = match dirs::home_dir() {
        Some(home) => home
            .join(".local")
            .join("share")
            .join("opencode")
            .join("storage"),
        None => return sessions,
    };

    if !storage_path.exists() {
        log::debug!(
            "OpenCode storage directory does not exist: {:?}",
            storage_path
        );
        return sessions;
    }

    // Build cwd -> process map
    let mut cwd_to_process: HashMap<String, &AgentProcess> = HashMap::new();
    for process in processes {
        if let Some(cwd) = &process.cwd {
            cwd_to_process.insert(cwd.to_string_lossy().to_string(), process);
        }
    }

    // Load all projects
    let projects = load_projects(&storage_path);
    log::debug!("Loaded {} OpenCode projects", projects.len());

    // Track which processes have been matched
    let mut matched_pids: std::collections::HashSet<u32> = std::collections::HashSet::new();

    // Match projects to running processes (non-global projects first)
    for project in &projects {
        if project.id == "global" {
            continue; // Handle global separately
        }

        if let Some(process) = find_matching_process(&cwd_to_process, project) {
            log::debug!(
                "Project {} matched to process pid={}",
                project.worktree,
                process.pid
            );
            matched_pids.insert(process.pid);
            if let Some(session) = get_latest_session_for_project(&storage_path, project, process) {
                sessions.push(session);
            }
        }
    }

    // For unmatched processes, check global sessions by directory field
    for process in processes {
        if matched_pids.contains(&process.pid) {
            continue;
        }
        if let Some(cwd) = &process.cwd {
            let cwd_str = cwd.to_string_lossy().to_string();
            if let Some(session) =
                get_global_session_for_directory(&storage_path, &cwd_str, process)
            {
                log::debug!(
                    "Global session matched for directory {} to process pid={}",
                    cwd_str,
                    process.pid
                );
                sessions.push(session);
            }
        }
    }

    sessions
}

/// Find a process that matches the given project's worktree or sandboxes
fn find_matching_process<'a>(
    cwd_to_process: &HashMap<String, &'a AgentProcess>,
    project: &OpenCodeProject,
) -> Option<&'a AgentProcess> {
    cwd_to_process
        .iter()
        .find(|(cwd, _)| {
            // Check if cwd matches the project worktree
            if cwd.as_str() == project.worktree
                || cwd.starts_with(&format!("{}/", project.worktree))
            {
                return true;
            }
            // Check if cwd matches any sandbox (worktree/branch)
            for sandbox in &project.sandboxes {
                if cwd.as_str() == sandbox || cwd.starts_with(&format!("{}/", sandbox)) {
                    return true;
                }
            }
            false
        })
        .map(|(_, p)| *p)
}

/// Get the latest session for a project
fn get_latest_session_for_project(
    storage_path: &PathBuf,
    project: &OpenCodeProject,
    process: &AgentProcess,
) -> Option<Session> {
    let session_dir = storage_path.join("session").join(&project.id);

    if !session_dir.exists() {
        return None;
    }

    let session = find_latest_session_in_dir(&session_dir, None)?;

    // Use actual process CWD for display (may be sandbox/worktree path)
    let actual_path = process
        .cwd
        .as_ref()
        .map(|p| p.to_string_lossy().to_string())
        .unwrap_or_else(|| project.worktree.clone());

    Some(build_session(storage_path, session, process, actual_path))
}

/// Get a global session matching a specific directory
fn get_global_session_for_directory(
    storage_path: &PathBuf,
    directory: &str,
    process: &AgentProcess,
) -> Option<Session> {
    let session_dir = storage_path.join("session").join("global");

    if !session_dir.exists() {
        return None;
    }

    let session = find_latest_session_in_dir(&session_dir, Some(directory))?;
    let project_path = session.directory.clone();

    Some(build_session(storage_path, session, process, project_path))
}
