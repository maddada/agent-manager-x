//! Notification script constants

// Voice notification script content (embedded)
pub const NOTIFICATION_SCRIPT: &str = r#"#!/bin/bash
# Voice notification script for Claude Code
# Reads hook metadata from stdin, loads transcript, and speaks the "Summary:" line via TTS

# Read hook metadata from stdin
INPUT=$(cat)

# Extract transcript_path from the hook metadata
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
    exit 0
fi

# Read the last assistant message from the JSONL transcript
# The format uses "type": "assistant" and content is at .message.content
CONTENT=$(tac "$TRANSCRIPT_PATH" | while read -r line; do
    msg_type=$(echo "$line" | jq -r '.type // empty')
    if [ "$msg_type" = "assistant" ]; then
        # Extract content from .message.content array
        echo "$line" | jq -r '
            .message.content |
            if type == "array" then
                map(select(.type == "text") | .text) | join("\n")
            elif type == "string" then
                .
            else
                empty
            end
        '
        break
    fi
done)

# Look for Summary: line (case insensitive)
SUMMARY=$(echo "$CONTENT" | grep -im1 "^Summary:" | sed 's/^[Ss]ummary:[[:space:]]*//')

if [ -n "$SUMMARY" ]; then
    say "$SUMMARY"
fi
"#;

pub const CLAUDE_MD_VOICE_SECTION: &str = r#"
## Voice Notifications

When completing a task and handing control back to the user, start your final message with a brief TLDR on the first line summarizing what was done. Format: `Summary: <summary>`. This line will be read aloud by the notification system to alert the user of task completion.

Example:
```
Summary: Fixed the authentication bug and added input validation.

Here are the details of what I changed...
```
"#;

// Bell mode script (plays sound instead of speaking)
pub const NOTIFICATION_SCRIPT_BELL: &str = r#"#!/bin/bash
# Voice notification script for Claude Code (Bell Mode)
# Reads hook metadata from stdin, loads transcript, and plays a bell if Summary found

# Read hook metadata from stdin
INPUT=$(cat)

# Extract transcript_path from the hook metadata
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
    exit 0
fi

# Read the last assistant message from the JSONL transcript
CONTENT=$(tac "$TRANSCRIPT_PATH" | while read -r line; do
    msg_type=$(echo "$line" | jq -r '.type // empty')
    if [ "$msg_type" = "assistant" ]; then
        echo "$line" | jq -r '
            .message.content |
            if type == "array" then
                map(select(.type == "text") | .text) | join("\n")
            elif type == "string" then
                .
            else
                empty
            end
        '
        break
    fi
done)

# Look for Summary: line (case insensitive)
SUMMARY=$(echo "$CONTENT" | grep -im1 "^Summary:")

if [ -n "$SUMMARY" ]; then
    afplay /System/Library/Sounds/Glass.aiff
fi
"#;
