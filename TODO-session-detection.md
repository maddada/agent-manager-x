# Session Detection Issues

## Fixed

### Path Matching with Underscore/Dash Differences
**Problem:** Project directories in `~/.claude/projects/` use dashes in names, but actual filesystem paths may have underscores. For example:
- Project dir: `-Users-madda-dev-z-OpenSourceEdits-agent-sessions`
- Actual CWD: `/Users/madda/dev/z_OpenSourceEdits/agent-sessions`

**Solution:** Added normalized comparison in `src-tauri/src/session/parser.rs` that treats underscores and dashes as equivalent:
```rust
let normalized_cwd = cwd_as_dir.replace('_', "-").to_lowercase();
let normalized_dir = dir_name.replace('_', "-").to_lowercase();
```

## Remaining Issues

### 1. Multiple Processes Same CWD
**Problem:** When two Claude processes share the same working directory, only one gets a session created.

**Example from logs:**
```
Found Claude process: pid=84289, cwd=/Users/madda/dev/z_OpenSourceEdits/agent-sessions
Found Claude process: pid=69442, cwd=/Users/madda/dev/z_OpenSourceEdits/agent-sessions
Session created: id=..., project=sessions, pid=84289 ✓
Failed to create session for process pid=69442 ✗
```

**Root cause:** The code in `find_session_for_process` uses an index to match processes to JSONL files. If there aren't enough recently-modified JSONL files for all processes, some fail.

**Location:** `src-tauri/src/session/parser.rs` - `get_recently_active_jsonl_files` and `find_session_for_process` functions

**Potential fix:** Instead of index-based matching, use process start time or JSONL file metadata to better correlate processes with their session files.

### 2. Sessions in ~/.claude Directory
**Problem:** Claude sessions run from `~/.claude` directory fail to create sessions.

**Example from logs:**
```
Found Claude process: pid=7322, cwd=/Users/madda/.claude
Project -Users-madda--claude matched via reverse lookup to cwd /Users/madda/.claude
Failed to create session for process pid=7322 in project /Users/madda//claude
```

**Note:** The reconstructed path has double slashes (`/Users/madda//claude`) which may cause issues.

**Location:** `src-tauri/src/session/parser.rs` - `convert_dir_name_to_path` function

**Potential fix:** Handle the special case of `.claude` directory, or fix path reconstruction for hidden directories.
