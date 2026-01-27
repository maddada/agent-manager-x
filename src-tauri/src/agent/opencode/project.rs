//! OpenCode project loading

use super::types::{OpenCodeProject, OpenCodeSession};
use std::path::PathBuf;

/// Load all project definitions from storage/project/*.json
pub fn load_projects(storage_path: &PathBuf) -> Vec<OpenCodeProject> {
    let project_dir = storage_path.join("project");
    let mut projects = Vec::new();

    if let Ok(entries) = std::fs::read_dir(&project_dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().map(|e| e == "json").unwrap_or(false) {
                if let Ok(content) = std::fs::read_to_string(&path) {
                    if let Ok(project) = serde_json::from_str::<OpenCodeProject>(&content) {
                        projects.push(project);
                    }
                }
            }
        }
    }

    projects
}

/// Find the latest session in a directory, optionally filtering by directory match
pub fn find_latest_session_in_dir(
    session_dir: &PathBuf,
    filter_directory: Option<&str>,
) -> Option<OpenCodeSession> {
    let mut latest_session: Option<(OpenCodeSession, u64)> = None;

    if let Ok(entries) = std::fs::read_dir(session_dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().map(|e| e == "json").unwrap_or(false) {
                if let Ok(content) = std::fs::read_to_string(&path) {
                    if let Ok(session) = serde_json::from_str::<OpenCodeSession>(&content) {
                        // If filtering by directory, check match
                        if let Some(dir) = filter_directory {
                            if dir != session.directory
                                && !dir.starts_with(&format!("{}/", session.directory))
                            {
                                continue;
                            }
                        }

                        let updated = session.time.updated;
                        if latest_session
                            .as_ref()
                            .map(|(_, t)| updated > *t)
                            .unwrap_or(true)
                        {
                            latest_session = Some((session, updated));
                        }
                    }
                }
            }
        }
    }

    latest_session.map(|(s, _)| s)
}
