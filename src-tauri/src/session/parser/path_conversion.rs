//! Path conversion utilities for mapping between file system paths and directory names.

/// Convert a file system path like "/Users/ozan/Projects/my-project" to a directory name
/// This is the reverse of convert_dir_name_to_path
/// e.g., "/Users/ozan/Projects/my-project/.rsworktree/branch-name" -> "-Users-ozan-Projects-my-project--rsworktree-branch-name"
pub fn convert_path_to_dir_name(path: &str) -> String {
    // Remove leading slash and replace path separators with dashes
    let path = path.strip_prefix('/').unwrap_or(path);

    let mut result = String::from("-");
    let mut chars = path.chars().peekable();

    while let Some(c) = chars.next() {
        match c {
            '/' => {
                // Check if next char starts a hidden folder (.)
                if chars.peek() == Some(&'.') {
                    // Hidden folder: use double dash and skip the dot
                    result.push('-');
                    result.push('-');
                    chars.next(); // skip the dot
                } else {
                    result.push('-');
                }
            }
            _ => result.push(c),
        }
    }

    result
}

/// Convert a directory name like "-Users-ozan-Projects-ai-image-dashboard" back to a path
/// The challenge is that both path separators AND project names can contain dashes
/// We handle this by recognizing that the path structure is predictable:
/// /Users/<username>/Projects/<project-name> or /Users/<username>/.../<project-name>
///
/// Special case: Double dashes (--) indicate a hidden folder (starting with .)
/// followed by subfolders separated by single dashes
/// e.g., "ai-image-dashboard--rsworktree-analytics" becomes "ai-image-dashboard/.rsworktree/analytics"
pub fn convert_dir_name_to_path(dir_name: &str) -> String {
    // Remove leading dash if present
    let name = dir_name.strip_prefix('-').unwrap_or(dir_name);

    // Split by dash
    let parts: Vec<&str> = name.split('-').collect();

    if parts.is_empty() {
        return String::new();
    }

    // Find "Projects" or "UnityProjects" index - everything after that is the project name
    let projects_idx = parts.iter().position(|&p| p == "Projects" || p == "UnityProjects");

    if let Some(idx) = projects_idx {
        // Path components are before and including "Projects"
        let path_parts = &parts[..=idx];
        // Project name is everything after "Projects"
        let project_parts = &parts[idx + 1..];

        let mut path = String::from("/");
        path.push_str(&path_parts.join("/"));

        if !project_parts.is_empty() {
            path.push('/');
            // Handle the project path with potential hidden folders
            // Double dash (empty string between dashes when split) indicates hidden folder
            // After a hidden folder marker, subsequent parts are subfolders
            let mut in_hidden_folder = false;
            let mut segments: Vec<String> = Vec::new();
            let mut current_segment = String::new();

            for part in project_parts {
                if part.is_empty() {
                    // Empty part means we hit a double dash - start hidden folder
                    if !current_segment.is_empty() {
                        segments.push(current_segment);
                        current_segment = String::new();
                    }
                    in_hidden_folder = true;
                } else if in_hidden_folder {
                    // After double dash, each part is a subfolder
                    // First part after -- gets the dot prefix
                    if current_segment.is_empty() {
                        current_segment = format!(".{}", part);
                    } else {
                        segments.push(current_segment);
                        current_segment = part.to_string();
                    }
                } else {
                    // Normal project name part - join with dashes
                    if current_segment.is_empty() {
                        current_segment = part.to_string();
                    } else {
                        current_segment.push('-');
                        current_segment.push_str(part);
                    }
                }
            }
            if !current_segment.is_empty() {
                segments.push(current_segment);
            }

            path.push_str(&segments.join("/"));
        }

        path
    } else {
        // Fallback: just replace dashes with slashes (old behavior)
        format!("/{}", name.replace('-', "/"))
    }
}
