use crate::session::{has_tool_use, has_tool_result, is_local_slash_command, is_interrupted_request};
use serde_json::json;

#[test]
fn test_has_tool_use() {
    // Array with tool_use block
    let content_with_tool_use = json!([
        {"type": "text", "text": "Let me run that command"},
        {"type": "tool_use", "id": "123", "name": "Bash", "input": {"command": "ls"}}
    ]);
    assert!(has_tool_use(&content_with_tool_use));

    // Array without tool_use
    let content_without_tool_use = json!([
        {"type": "text", "text": "Here is the result"}
    ]);
    assert!(!has_tool_use(&content_without_tool_use));

    // Empty array
    let empty_array = json!([]);
    assert!(!has_tool_use(&empty_array));

    // String content (not an array)
    let string_content = json!("Just a string");
    assert!(!has_tool_use(&string_content));

    // Array with tool_result (not tool_use)
    let content_with_tool_result = json!([
        {"type": "tool_result", "tool_use_id": "123", "content": "output"}
    ]);
    assert!(!has_tool_use(&content_with_tool_result));
}

#[test]
fn test_has_tool_result() {
    // Array with tool_result block
    let content_with_tool_result = json!([
        {"type": "tool_result", "tool_use_id": "123", "content": "command output"}
    ]);
    assert!(has_tool_result(&content_with_tool_result));

    // Array without tool_result
    let content_without_tool_result = json!([
        {"type": "text", "text": "Just text"}
    ]);
    assert!(!has_tool_result(&content_without_tool_result));

    // Empty array
    let empty_array = json!([]);
    assert!(!has_tool_result(&empty_array));

    // String content (not an array)
    let string_content = json!("Just a string");
    assert!(!has_tool_result(&string_content));

    // Array with tool_use (not tool_result)
    let content_with_tool_use = json!([
        {"type": "tool_use", "id": "123", "name": "Read"}
    ]);
    assert!(!has_tool_result(&content_with_tool_use));
}

#[test]
fn test_is_local_slash_command() {
    // Test recognized local commands
    assert!(is_local_slash_command(&json!("/clear")));
    assert!(is_local_slash_command(&json!("/compact")));
    assert!(is_local_slash_command(&json!("/help")));
    assert!(is_local_slash_command(&json!("/config")));
    assert!(is_local_slash_command(&json!("/cost")));
    assert!(is_local_slash_command(&json!("/doctor")));
    assert!(is_local_slash_command(&json!("/init")));
    assert!(is_local_slash_command(&json!("/login")));
    assert!(is_local_slash_command(&json!("/logout")));
    assert!(is_local_slash_command(&json!("/memory")));
    assert!(is_local_slash_command(&json!("/model")));
    assert!(is_local_slash_command(&json!("/permissions")));
    assert!(is_local_slash_command(&json!("/pr-comments")));
    assert!(is_local_slash_command(&json!("/review")));
    assert!(is_local_slash_command(&json!("/status")));
    assert!(is_local_slash_command(&json!("/terminal-setup")));
    assert!(is_local_slash_command(&json!("/vim")));

    // Test commands with arguments
    assert!(is_local_slash_command(&json!("/model sonnet")));
    assert!(is_local_slash_command(&json!("/memory add something")));

    // Test commands with whitespace
    assert!(is_local_slash_command(&json!("  /clear  ")));

    // Test non-local commands (these trigger Claude)
    assert!(!is_local_slash_command(&json!("Hello Claude")));
    assert!(!is_local_slash_command(&json!("/custom-command")));
    assert!(!is_local_slash_command(&json!("/fix the bug")));

    // Test array content with text block
    let array_content = json!([
        {"type": "text", "text": "/clear"}
    ]);
    assert!(is_local_slash_command(&array_content));

    // Test array content with non-local command
    let array_non_local = json!([
        {"type": "text", "text": "fix the bug"}
    ]);
    assert!(!is_local_slash_command(&array_non_local));

    // Test empty and edge cases
    assert!(!is_local_slash_command(&json!("")));
    assert!(!is_local_slash_command(&json!(null)));
    assert!(!is_local_slash_command(&json!(123)));
}

#[test]
fn test_is_interrupted_request() {
    // Message with interruption text
    assert!(is_interrupted_request(&json!("[Request interrupted by user]")));
    assert!(is_interrupted_request(&json!("Some text [Request interrupted by user] more text")));

    // Array content with interruption
    let array_content = json!([
        {"type": "text", "text": "[Request interrupted by user]"}
    ]);
    assert!(is_interrupted_request(&array_content));

    // Normal messages
    assert!(!is_interrupted_request(&json!("Hello Claude")));
    assert!(!is_interrupted_request(&json!("Fix the bug")));
    assert!(!is_interrupted_request(&json!("")));
}
