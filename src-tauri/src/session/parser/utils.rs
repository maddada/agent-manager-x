//! Utility functions for session parsing.

use std::process::Command;

/// Extract a preview of content for debugging
pub fn get_content_preview(content: &serde_json::Value) -> String {
    match content {
        serde_json::Value::String(s) => {
            let preview: String = s.chars().take(100).collect();
            format!("text: \"{}{}\"", preview, if s.len() > 100 { "..." } else { "" })
        }
        serde_json::Value::Array(arr) => {
            let types: Vec<String> = arr.iter()
                .filter_map(|v| v.get("type").and_then(|t| t.as_str()).map(String::from))
                .collect();
            format!("blocks: [{}]", types.join(", "))
        }
        _ => "unknown".to_string(),
    }
}

/// Get GitHub URL from a project's git remote origin
pub fn get_github_url(project_path: &str) -> Option<String> {
    let output = Command::new("git")
        .args(["remote", "get-url", "origin"])
        .current_dir(project_path)
        .output()
        .ok()?;

    if !output.status.success() {
        return None;
    }

    let remote_url = String::from_utf8_lossy(&output.stdout).trim().to_string();

    // Convert SSH format to HTTPS
    // git@github.com:user/repo.git -> https://github.com/user/repo
    if remote_url.starts_with("git@github.com:") {
        let path = remote_url
            .strip_prefix("git@github.com:")?
            .strip_suffix(".git")
            .unwrap_or(&remote_url[15..]);
        return Some(format!("https://github.com/{}", path));
    }

    // Already HTTPS format
    // https://github.com/user/repo.git -> https://github.com/user/repo
    if remote_url.starts_with("https://github.com/") {
        let url = remote_url
            .strip_suffix(".git")
            .unwrap_or(&remote_url);
        return Some(url.to_string());
    }

    None
}
