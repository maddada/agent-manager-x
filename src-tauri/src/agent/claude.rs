use super::{AgentDetector, AgentProcess};
use crate::process::find_claude_processes;
use crate::session::parser::get_sessions_internal;
use crate::session::{AgentType, Session};
use std::path::PathBuf;
use std::process::Command;

pub struct ClaudeDetector;

impl AgentDetector for ClaudeDetector {
    fn name(&self) -> &'static str {
        "Claude Code"
    }

    fn agent_type(&self) -> AgentType {
        AgentType::Claude
    }

    fn find_processes(&self) -> Vec<AgentProcess> {
        find_claude_processes()
            .into_iter()
            .map(|p| AgentProcess {
                pid: p.pid,
                cpu_usage: p.cpu_usage,
                memory_bytes: p.memory,
                cwd: p.cwd,
                data_home: None,
                active_session_file: find_open_claude_session_file(p.pid),
            })
            .collect()
    }

    fn find_sessions(&self, processes: &[AgentProcess]) -> Vec<Session> {
        get_sessions_internal(processes, AgentType::Claude)
    }
}

fn find_open_claude_session_file(pid: u32) -> Option<PathBuf> {
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

        if !path_str.ends_with(".jsonl") || !path_str.contains("/projects/") {
            continue;
        }
        if !path_str.contains("/.claude") {
            continue;
        }
        if PathBuf::from(path_str)
            .file_name()
            .and_then(|name| name.to_str())
            .map(|name| name.starts_with("agent-"))
            .unwrap_or(false)
        {
            // Skip subagent files; we only want the main session file.
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
