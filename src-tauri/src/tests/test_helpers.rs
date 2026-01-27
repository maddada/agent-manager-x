use std::io::Write;
use std::time::{SystemTime, Duration};
use tempfile::NamedTempFile;

/// Create a test JSONL file with the given lines
pub fn create_test_jsonl(lines: &[&str]) -> NamedTempFile {
    let mut file = NamedTempFile::new().unwrap();
    for line in lines {
        writeln!(file, "{}", line).unwrap();
    }
    file.flush().unwrap();
    file
}

/// Create a test JSONL file with an old modification time (>3s ago)
/// This ensures file_recently_modified = false in status determination
pub fn create_test_jsonl_old(lines: &[&str]) -> NamedTempFile {
    let file = create_test_jsonl(lines);
    // Set modification time to 10 seconds ago
    let old_time = SystemTime::now() - Duration::from_secs(10);
    let old_time_file = filetime::FileTime::from_system_time(old_time);
    filetime::set_file_mtime(file.path(), old_time_file).unwrap();
    file
}

/// Generate a recent timestamp (within 1 minute) for test messages
/// This prevents time-based status upgrades to Idle/Stale in tests
pub fn recent_timestamp() -> String {
    chrono::Utc::now().to_rfc3339()
}

/// Generate a timestamp that's old enough to trigger Stale status (10+ minutes)
#[allow(dead_code)]
pub fn stale_timestamp() -> String {
    (chrono::Utc::now() - chrono::Duration::minutes(15)).to_rfc3339()
}

// Test constants for process info
pub const TEST_PID: u32 = 12345;
pub const TEST_CPU_USAGE: f32 = 0.0;
