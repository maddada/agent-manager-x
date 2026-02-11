//! Process management command handlers

use std::process::Command;
use std::thread;
use std::time::Duration;

/// Recursively get all descendant PIDs of a process
fn get_descendant_pids(pid: u32) -> Vec<u32> {
    let mut descendants = Vec::new();

    // Get direct children using pgrep -P
    if let Ok(output) = Command::new("pgrep")
        .args(["-P", &pid.to_string()])
        .output()
    {
        if output.status.success() {
            let stdout = String::from_utf8_lossy(&output.stdout);
            for line in stdout.lines() {
                if let Ok(child_pid) = line.trim().parse::<u32>() {
                    // Recursively get grandchildren first (kill bottom-up)
                    descendants.extend(get_descendant_pids(child_pid));
                    descendants.push(child_pid);
                }
            }
        }
    }

    descendants
}

/// Check if a process is still running
fn is_process_running(pid: u32) -> bool {
    Command::new("kill")
        .args(["-0", &pid.to_string()])
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}

/// Kill a single process with SIGKILL
fn kill_pid(pid: u32) {
    let _ = Command::new("kill").args(["-9", &pid.to_string()]).output();
}

/// Kill an agent process and all its descendants by PID
#[tauri::command]
pub fn kill_session(pid: u32) -> Result<(), String> {
    // Get all descendant PIDs (children, grandchildren, etc.)
    let descendants = get_descendant_pids(pid);

    // Kill descendants first (bottom-up to avoid orphaning)
    for child_pid in &descendants {
        kill_pid(*child_pid);
    }

    // Kill the main process with SIGKILL (-9)
    kill_pid(pid);

    // Also try to kill the process group (negative PID)
    // This catches any processes that spawned with the same PGID
    let _ = Command::new("kill")
        .args(["-9", &format!("-{}", pid)])
        .output();

    // Brief wait then verify and retry if needed
    thread::sleep(Duration::from_millis(50));

    // If still running, try again more aggressively
    if is_process_running(pid) {
        // Re-fetch descendants (new ones may have spawned)
        let new_descendants = get_descendant_pids(pid);
        for child_pid in &new_descendants {
            kill_pid(*child_pid);
        }
        kill_pid(pid);

        // Final check
        thread::sleep(Duration::from_millis(50));
        if is_process_running(pid) {
            return Err(format!(
                "Process {} still running after multiple kill attempts",
                pid
            ));
        }
    }

    Ok(())
}
