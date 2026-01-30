use super::{AgentDetector, AgentProcess};
use crate::process::find_claude_processes;
use crate::session::{AgentType, Session};
use crate::session::parser::get_sessions_internal;

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
            })
            .collect()
    }

    fn find_sessions(&self, processes: &[AgentProcess]) -> Vec<Session> {
        get_sessions_internal(processes, AgentType::Claude)
    }
}
