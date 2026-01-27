use crate::session::{AgentType, SessionStatus, parse_session_file};
use super::test_helpers::{create_test_jsonl, create_test_jsonl_old, recent_timestamp, TEST_PID, TEST_CPU_USAGE};

#[test]
fn test_parse_jsonl_assistant_text_only_is_waiting() {
    // Scenario: Claude responded with text only (no tool_use), file not recently modified
    // Expected: Waiting (using recent timestamp to avoid Idle/Stale upgrade)
    let ts = recent_timestamp();
    let jsonl = create_test_jsonl_old(&[
        &format!(r#"{{"sessionId":"test-session","type":"user","message":{{"role":"user","content":"Hello Claude"}},"timestamp":"{}"}}"#, ts),
        &format!(r#"{{"sessionId":"test-session","type":"assistant","message":{{"role":"assistant","content":[{{"type":"text","text":"Hello! How can I help you today?"}}]}},"timestamp":"{}"}}"#, ts),
    ]);

    let session = parse_session_file(&jsonl.path().to_path_buf(), "/Users/test/Projects/test-project", TEST_PID, TEST_CPU_USAGE, AgentType::Claude);

    assert!(session.is_some());
    let session = session.unwrap();
    assert!(matches!(session.status, SessionStatus::Waiting),
        "Expected Waiting when last message is assistant text-only, got {:?}", session.status);
}

#[test]
fn test_parse_jsonl_assistant_with_tool_use_is_processing() {
    // Scenario: Claude sent a tool_use (waiting for tool execution)
    // Expected: Processing
    let jsonl = create_test_jsonl(&[
        r#"{"sessionId":"test-session","type":"user","message":{"role":"user","content":"List files"},"timestamp":"2024-01-01T00:00:00Z"}"#,
        r#"{"sessionId":"test-session","type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Let me list the files"},{"type":"tool_use","id":"123","name":"Bash","input":{"command":"ls"}}]},"timestamp":"2024-01-01T00:00:01Z"}"#,
    ]);

    let session = parse_session_file(&jsonl.path().to_path_buf(), "/Users/test/Projects/test-project", TEST_PID, TEST_CPU_USAGE, AgentType::Claude);

    assert!(session.is_some());
    let session = session.unwrap();
    assert!(matches!(session.status, SessionStatus::Processing),
        "Expected Processing when last message is assistant with tool_use, got {:?}", session.status);
}

#[test]
fn test_parse_jsonl_user_message_is_thinking() {
    // Scenario: User just sent a message (Claude is thinking)
    // Expected: Thinking
    let jsonl = create_test_jsonl(&[
        r#"{"sessionId":"test-session","type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"How can I help?"}]},"timestamp":"2024-01-01T00:00:00Z"}"#,
        r#"{"sessionId":"test-session","type":"user","message":{"role":"user","content":"Fix the bug in main.rs"},"timestamp":"2024-01-01T00:00:01Z"}"#,
    ]);

    let session = parse_session_file(&jsonl.path().to_path_buf(), "/Users/test/Projects/test-project", TEST_PID, TEST_CPU_USAGE, AgentType::Claude);

    assert!(session.is_some());
    let session = session.unwrap();
    assert!(matches!(session.status, SessionStatus::Thinking),
        "Expected Thinking when last message is user input, got {:?}", session.status);
}

#[test]
fn test_parse_jsonl_user_tool_result_is_thinking() {
    // Scenario: Tool result was just sent, Claude processing it
    // The tempfile is freshly created so file_recently_modified = true
    // Expected: Thinking (Claude is actively processing the tool result)
    let jsonl = create_test_jsonl(&[
        r#"{"sessionId":"test-session","type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"123","name":"Bash","input":{"command":"ls"}}]},"timestamp":"2024-01-01T00:00:00Z"}"#,
        r#"{"sessionId":"test-session","type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"123","content":"file1.txt\nfile2.txt"}]},"timestamp":"2024-01-01T00:00:01Z"}"#,
    ]);

    let session = parse_session_file(&jsonl.path().to_path_buf(), "/Users/test/Projects/test-project", TEST_PID, TEST_CPU_USAGE, AgentType::Claude);

    assert!(session.is_some());
    let session = session.unwrap();
    // Since the tempfile was just created, file_recently_modified = true
    // With tool_result + recently modified = Thinking
    assert!(matches!(session.status, SessionStatus::Thinking),
        "Expected Thinking when last message is tool_result with recently modified file, got {:?}", session.status);
}

#[test]
fn test_parse_jsonl_local_command_is_waiting() {
    // Scenario: User typed /clear or other local command
    // Expected: Waiting (local commands don't trigger Claude)
    let ts = recent_timestamp();
    let jsonl = create_test_jsonl(&[
        &format!(r#"{{"sessionId":"test-session","type":"assistant","message":{{"role":"assistant","content":[{{"type":"text","text":"Done!"}}]}},"timestamp":"{}"}}"#, ts),
        &format!(r#"{{"sessionId":"test-session","type":"user","message":{{"role":"user","content":"/clear"}},"timestamp":"{}"}}"#, ts),
    ]);

    let session = parse_session_file(&jsonl.path().to_path_buf(), "/Users/test/Projects/test-project", TEST_PID, TEST_CPU_USAGE, AgentType::Claude);

    assert!(session.is_some());
    let session = session.unwrap();
    assert!(matches!(session.status, SessionStatus::Waiting),
        "Expected Waiting when last message is local command, got {:?}", session.status);
}

#[test]
fn test_parse_jsonl_complex_conversation_flow() {
    // Scenario: Complex conversation - user asks, Claude responds with tool, tool runs, Claude responds with text
    // File is old (not recently modified), using recent timestamp to avoid Idle/Stale
    // Expected: Waiting (Claude finished with text response)
    let ts = recent_timestamp();
    let jsonl = create_test_jsonl_old(&[
        &format!(r#"{{"sessionId":"test-session","type":"user","message":{{"role":"user","content":"What files are in this directory?"}},"timestamp":"{}"}}"#, ts),
        &format!(r#"{{"sessionId":"test-session","type":"assistant","message":{{"role":"assistant","content":[{{"type":"tool_use","id":"tool1","name":"Bash","input":{{"command":"ls -la"}}}}]}},"timestamp":"{}"}}"#, ts),
        &format!(r#"{{"sessionId":"test-session","type":"user","message":{{"role":"user","content":[{{"type":"tool_result","tool_use_id":"tool1","content":"file1.txt\nfile2.txt"}}]}},"timestamp":"{}"}}"#, ts),
        &format!(r#"{{"sessionId":"test-session","type":"assistant","message":{{"role":"assistant","content":[{{"type":"text","text":"I found 2 files: file1.txt and file2.txt"}}]}},"timestamp":"{}"}}"#, ts),
    ]);

    let session = parse_session_file(&jsonl.path().to_path_buf(), "/Users/test/Projects/test-project", TEST_PID, TEST_CPU_USAGE, AgentType::Claude);

    assert!(session.is_some());
    let session = session.unwrap();
    assert!(matches!(session.status, SessionStatus::Waiting),
        "Expected Waiting after Claude responds with text, got {:?}", session.status);
}

#[test]
fn test_parse_jsonl_multiple_tool_calls_in_progress() {
    // Scenario: Claude sent tool_use, waiting for result
    // Expected: Processing
    let jsonl = create_test_jsonl(&[
        r#"{"sessionId":"test-session","type":"user","message":{"role":"user","content":"Run tests and check coverage"},"timestamp":"2024-01-01T00:00:00Z"}"#,
        r#"{"sessionId":"test-session","type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"I'll run the tests first"},{"type":"tool_use","id":"tool1","name":"Bash","input":{"command":"npm test"}}]},"timestamp":"2024-01-01T00:00:01Z"}"#,
    ]);

    let session = parse_session_file(&jsonl.path().to_path_buf(), "/Users/test/Projects/test-project", TEST_PID, TEST_CPU_USAGE, AgentType::Claude);

    assert!(session.is_some());
    let session = session.unwrap();
    assert!(matches!(session.status, SessionStatus::Processing),
        "Expected Processing when tool is executing, got {:?}", session.status);
}

#[test]
fn test_parse_jsonl_empty_content_skipped() {
    // Scenario: Some messages have empty content, should skip to find real message
    // File is old (not recently modified), using recent timestamp to avoid Idle/Stale
    let ts = recent_timestamp();
    let jsonl = create_test_jsonl_old(&[
        &format!(r#"{{"sessionId":"test-session","type":"user","message":{{"role":"user","content":"Hello"}},"timestamp":"{}"}}"#, ts),
        &format!(r#"{{"sessionId":"test-session","type":"assistant","message":{{"role":"assistant","content":[]}},"timestamp":"{}"}}"#, ts),
        &format!(r#"{{"sessionId":"test-session","type":"assistant","message":{{"role":"assistant","content":[{{"type":"text","text":"Hi there!"}}]}},"timestamp":"{}"}}"#, ts),
    ]);

    let session = parse_session_file(&jsonl.path().to_path_buf(), "/Users/test/Projects/test-project", TEST_PID, TEST_CPU_USAGE, AgentType::Claude);

    assert!(session.is_some());
    let session = session.unwrap();
    // The parser reads from the end, so it should find the last non-empty message
    assert!(matches!(session.status, SessionStatus::Waiting),
        "Expected Waiting after finding text-only assistant message, got {:?}", session.status);
}
