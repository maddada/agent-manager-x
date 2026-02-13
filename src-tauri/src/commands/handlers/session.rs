//! Session-related command handlers

use crate::session::{get_sessions, SessionsResponse};
use crate::terminal;
use serde::Serialize;
use std::process::Command;

#[derive(Debug, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GitDiffStats {
    pub additions: u64,
    pub deletions: u64,
}

/// Get all active Claude Code sessions
#[tauri::command]
pub fn get_all_sessions() -> SessionsResponse {
    get_sessions()
}

/// Focus the terminal containing a specific session
#[tauri::command]
pub fn focus_session(pid: u32, project_path: String) -> Result<(), String> {
    terminal::focus_terminal_for_pid(pid)
        .or_else(|_| terminal::focus_terminal_by_path(&project_path))
}

/// Get git line-change summary for a project path (`+additions -deletions`)
#[tauri::command]
pub fn get_project_git_diff_stats(project_path: String) -> Result<GitDiffStats, String> {
    let output = Command::new("git")
        .args(["-C", &project_path, "diff", "--numstat", "HEAD"])
        .output()
        .map_err(|error| {
            format!(
                "Failed to run git diff for project path {}: {}",
                project_path, error
            )
        })?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        let stderr_text = stderr.trim();

        // Missing git metadata or HEAD should not break the UI; treat as no diff.
        if stderr_text.contains("not a git repository")
            || stderr_text.contains("bad revision 'HEAD'")
            || stderr_text.contains("ambiguous argument 'HEAD'")
            || stderr_text.contains("unknown revision or path not in the working tree")
        {
            return Ok(GitDiffStats::default());
        }

        return Err(format!(
            "git diff failed for project path {}: {}",
            project_path, stderr_text
        ));
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let mut stats = GitDiffStats::default();

    for line in stdout.lines() {
        let mut columns = line.split('\t');
        let additions = columns.next().unwrap_or_default();
        let deletions = columns.next().unwrap_or_default();

        if let Ok(value) = additions.parse::<u64>() {
            stats.additions += value;
        }
        if let Ok(value) = deletions.parse::<u64>() {
            stats.deletions += value;
        }
    }

    Ok(stats)
}
