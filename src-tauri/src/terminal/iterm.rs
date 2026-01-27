use super::applescript::execute_applescript;

/// Focus iTerm2 tab/session by TTY
pub fn focus_iterm_by_tty(tty: &str) -> Result<(), String> {
    let script = format!(r#"
        tell application "System Events"
            if not (exists process "iTerm2") then
                error "iTerm2 not running"
            end if
        end tell

        tell application "iTerm2"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s contains "{}" then
                            select s
                            select t
                            set index of w to 1
                            return "found"
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return "not found"
    "#, tty);

    execute_applescript(&script)
}
