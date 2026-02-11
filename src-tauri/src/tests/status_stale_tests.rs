// Tests for stale message handling in determine_status
use crate::session::{determine_status, SessionStatus};

#[test]
fn test_determine_status_stale_assistant_message() {
    // When message is stale (>30s old) and file not recently modified,
    // the session should return early with Waiting regardless of other factors

    // Stale assistant message -> Waiting
    let status = determine_status(
        Some("assistant"),
        true, // has_tool_use (normally would be Processing)
        false,
        false,
        false,
        false, // file_recently_modified
        true,  // message_is_stale - this overrides!
    );
    assert!(
        matches!(status, SessionStatus::Waiting),
        "Stale assistant message should be Waiting, got {:?}",
        status
    );
}

#[test]
fn test_determine_status_stale_user_message() {
    // Stale user message -> Waiting
    let status = determine_status(
        Some("user"),
        false,
        false,
        false,
        false,
        false, // file_recently_modified
        true,  // message_is_stale - this overrides!
    );
    assert!(
        matches!(status, SessionStatus::Waiting),
        "Stale user message should be Waiting, got {:?}",
        status
    );
}

#[test]
fn test_determine_status_stale_unknown_type() {
    // Stale unknown type -> Idle
    let status = determine_status(
        None, false, false, false, false, false, // file_recently_modified
        true,  // message_is_stale
    );
    assert!(
        matches!(status, SessionStatus::Idle),
        "Stale unknown message should be Idle, got {:?}",
        status
    );
}

#[test]
fn test_determine_status_stale_with_recent_file() {
    // IMPORTANT: Stale message BUT file recently modified -> still use normal logic
    // (file activity takes precedence over message staleness)
    let status = determine_status(
        Some("user"),
        false,
        false,
        false,
        false,
        true, // file_recently_modified - takes precedence!
        true, // message_is_stale
    );
    assert!(
        matches!(status, SessionStatus::Thinking),
        "Recent file activity should override staleness, got {:?}",
        status
    );
}
