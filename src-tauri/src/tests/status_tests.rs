// Tests for the determine_status function
use crate::session::{SessionStatus, determine_status};

#[test]
fn test_determine_status_assistant_with_tool_use() {
    // Assistant message with tool_use but stale file -> Waiting (stuck)
    let status = determine_status(
        Some("assistant"),
        true,  // has_tool_use
        false, // has_tool_result
        false, // is_local_command
        false, // is_interrupted
        false, // file_recently_modified - stale means stuck
        false, // message_is_stale
    );
    assert!(matches!(status, SessionStatus::Waiting));

    // With file recently modified, tool_use means Processing (actively running)
    let status = determine_status(
        Some("assistant"),
        true,
        false,
        false,
        false,
        true,  // file_recently_modified
        false, // message_is_stale
    );
    assert!(matches!(status, SessionStatus::Processing));
}

#[test]
fn test_determine_status_assistant_text_only() {
    // Assistant message with only text -> Waiting
    let status = determine_status(
        Some("assistant"),
        false, // no tool_use
        false,
        false,
        false, // is_interrupted
        false,
        false, // message_is_stale
    );
    assert!(matches!(status, SessionStatus::Waiting));

    // If file was recently modified, treat as Processing (Claude may still be streaming)
    let status = determine_status(
        Some("assistant"),
        false,
        false,
        false,
        false, // is_interrupted
        true,  // file_recently_modified
        false, // message_is_stale
    );
    assert!(matches!(status, SessionStatus::Processing));
}

#[test]
fn test_determine_status_user_message_recent() {
    // Regular user message with recent activity -> Thinking (Claude generating response)
    let status = determine_status(
        Some("user"),
        false,
        false,
        false, // not a local command
        false, // is_interrupted
        true,  // file_recently_modified - actively responding
        false, // message_is_stale
    );
    assert!(matches!(status, SessionStatus::Thinking));
}

#[test]
fn test_determine_status_user_message_stale() {
    // Regular user message but stale -> Waiting (Claude not responding)
    let status = determine_status(
        Some("user"),
        false,
        false,
        false, // not a local command
        false, // is_interrupted
        false, // file not recently modified - stuck
        false, // message_is_stale
    );
    assert!(matches!(status, SessionStatus::Waiting));
}

#[test]
fn test_determine_status_user_local_command() {
    // User message that's a local command -> Waiting
    let status = determine_status(
        Some("user"),
        false,
        false,
        true,  // is_local_command
        false, // is_interrupted
        false,
        false, // message_is_stale
    );
    assert!(matches!(status, SessionStatus::Waiting));
}

#[test]
fn test_determine_status_user_interrupted() {
    // User message that's an interrupted request -> Waiting
    let status = determine_status(
        Some("user"),
        false,
        false,
        false,
        true,  // is_interrupted
        false,
        false, // message_is_stale
    );
    assert!(matches!(status, SessionStatus::Waiting));
}

#[test]
fn test_determine_status_user_with_tool_result() {
    // User message with tool_result and recent file modification -> Thinking
    let status = determine_status(
        Some("user"),
        false,
        true,  // has_tool_result
        false,
        false, // is_interrupted
        true,  // file_recently_modified
        false, // message_is_stale
    );
    assert!(matches!(status, SessionStatus::Thinking));

    // User message with tool_result but stale -> Waiting (stuck)
    let status = determine_status(
        Some("user"),
        false,
        true,  // has_tool_result
        false,
        false, // is_interrupted
        false, // not recently modified - stuck
        false, // message_is_stale
    );
    assert!(matches!(status, SessionStatus::Waiting));
}

#[test]
fn test_determine_status_unknown_type() {
    // Unknown message type with recent file activity -> Thinking
    let status = determine_status(
        None,
        false,
        false,
        false,
        false, // is_interrupted
        true,  // file_recently_modified
        false, // message_is_stale
    );
    assert!(matches!(status, SessionStatus::Thinking));

    // Unknown message type without recent activity -> Idle
    let status = determine_status(
        None,
        false,
        false,
        false,
        false, // is_interrupted
        false,
        false, // message_is_stale
    );
    assert!(matches!(status, SessionStatus::Idle));
}
