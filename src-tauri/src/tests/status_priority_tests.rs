// Tests for status sorting priority and serialization
use crate::session::{SessionStatus, status_sort_priority};

#[test]
fn test_status_sort_priority() {
    // Thinking and Processing have highest priority (0)
    assert_eq!(status_sort_priority(&SessionStatus::Thinking), 0);
    assert_eq!(status_sort_priority(&SessionStatus::Processing), 0);

    // Waiting has second priority (1)
    assert_eq!(status_sort_priority(&SessionStatus::Waiting), 1);

    // Idle has third priority (2)
    assert_eq!(status_sort_priority(&SessionStatus::Idle), 2);

    // Stale has lowest priority (3)
    assert_eq!(status_sort_priority(&SessionStatus::Stale), 3);

    // Verify ordering: Thinking/Processing < Waiting < Idle < Stale
    assert!(status_sort_priority(&SessionStatus::Thinking) < status_sort_priority(&SessionStatus::Waiting));
    assert!(status_sort_priority(&SessionStatus::Waiting) < status_sort_priority(&SessionStatus::Idle));
    assert!(status_sort_priority(&SessionStatus::Idle) < status_sort_priority(&SessionStatus::Stale));
}

#[test]
fn test_session_status_serialization() {
    // Verify status serializes to lowercase
    let waiting = SessionStatus::Waiting;
    let serialized = serde_json::to_string(&waiting).unwrap();
    assert_eq!(serialized, "\"waiting\"");

    let thinking = SessionStatus::Thinking;
    let serialized = serde_json::to_string(&thinking).unwrap();
    assert_eq!(serialized, "\"thinking\"");

    let processing = SessionStatus::Processing;
    let serialized = serde_json::to_string(&processing).unwrap();
    assert_eq!(serialized, "\"processing\"");

    let idle = SessionStatus::Idle;
    let serialized = serde_json::to_string(&idle).unwrap();
    assert_eq!(serialized, "\"idle\"");

    let stale = SessionStatus::Stale;
    let serialized = serde_json::to_string(&stale).unwrap();
    assert_eq!(serialized, "\"stale\"");
}
