use crate::process::{find_claude_processes, ClaudeProcess};
use std::path::PathBuf;

#[test]
fn test_claude_process_creation() {
    let process = ClaudeProcess {
        pid: 12345,
        cwd: Some(PathBuf::from("/Users/test/Projects/my-project")),
        cpu_usage: 5.5,
        memory: 1024,
    };

    assert_eq!(process.pid, 12345);
    assert_eq!(
        process.cwd,
        Some(PathBuf::from("/Users/test/Projects/my-project"))
    );
    assert_eq!(process.cpu_usage, 5.5);
    assert_eq!(process.memory, 1024);
}

#[test]
fn test_claude_process_without_cwd() {
    let process = ClaudeProcess {
        pid: 99999,
        cwd: None,
        cpu_usage: 0.0,
        memory: 0,
    };

    assert_eq!(process.pid, 99999);
    assert!(process.cwd.is_none());
}

#[test]
fn test_claude_process_clone() {
    let process = ClaudeProcess {
        pid: 12345,
        cwd: Some(PathBuf::from("/test/path")),
        cpu_usage: 10.0,
        memory: 2048,
    };

    let cloned = process.clone();
    assert_eq!(process.pid, cloned.pid);
    assert_eq!(process.cwd, cloned.cwd);
    assert_eq!(process.cpu_usage, cloned.cpu_usage);
    assert_eq!(process.memory, cloned.memory);
}

#[test]
fn test_claude_process_serialization() {
    let process = ClaudeProcess {
        pid: 12345,
        cwd: Some(PathBuf::from("/test/path")),
        cpu_usage: 5.5,
        memory: 1024,
    };

    let json = serde_json::to_string(&process).unwrap();
    assert!(json.contains("12345"));
    assert!(json.contains("5.5"));
}

#[test]
fn test_find_claude_processes_returns_vec() {
    // This test just ensures the function runs without panicking
    // In a real environment, it may or may not find Claude processes
    let processes = find_claude_processes();
    // Should return a Vec (possibly empty) - just verify we got a result
    let _ = processes.len();
}
