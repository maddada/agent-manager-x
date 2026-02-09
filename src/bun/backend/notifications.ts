import {
  chmodSync,
  existsSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { join } from 'node:path';

const NOTIFICATION_SCRIPT = `#!/bin/bash
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
                map(select(.type == "text") | .text) | join("\\n")
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
`;

const NOTIFICATION_SCRIPT_BELL = `#!/bin/bash
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
                map(select(.type == "text") | .text) | join("\\n")
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
`;

const CLAUDE_MD_VOICE_SECTION = `
## Voice Notifications

When completing a task and handing control back to the user, start your final message with a brief TLDR on the first line summarizing what was done. Format: \`Summary: <summary>\`. This line will be read aloud by the notification system to alert the user of task completion.

Example:
\`\`\`
Summary: Fixed the authentication bug and added input validation.

Here are the details of what I changed...
\`\`\`
`;

function getHomeDir(): string {
  const home = process.env.HOME;
  if (!home) {
    throw new Error('Could not get HOME directory');
  }
  return home;
}

function hookContainsNotificationScript(entry: unknown): boolean {
  if (!entry || typeof entry !== 'object') {
    return false;
  }

  const hooks = (entry as { hooks?: unknown }).hooks;
  if (!Array.isArray(hooks)) {
    return false;
  }

  for (const hook of hooks) {
    if (!hook || typeof hook !== 'object') {
      continue;
    }
    const command = (hook as { command?: unknown }).command;
    if (typeof command === 'string' && command.includes('notify-local-tts.sh')) {
      return true;
    }
  }

  return false;
}

function readSettingsOrDefault(settingsPath: string): Record<string, unknown> {
  if (!existsSync(settingsPath)) {
    return {};
  }

  const parsed = JSON.parse(readFileSync(settingsPath, 'utf8')) as unknown;
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
    throw new Error('Settings is not an object');
  }
  return parsed as Record<string, unknown>;
}

export function checkNotificationSystem(): boolean {
  const settingsPath = join(getHomeDir(), '.claude', 'settings.json');
  if (!existsSync(settingsPath)) {
    return false;
  }

  const parsed = JSON.parse(readFileSync(settingsPath, 'utf8')) as unknown;
  if (!parsed || typeof parsed !== 'object') {
    return false;
  }

  const hooks = (parsed as { hooks?: unknown }).hooks;
  if (!hooks || typeof hooks !== 'object') {
    return false;
  }

  const stopHooks = (hooks as { Stop?: unknown }).Stop;
  if (!Array.isArray(stopHooks)) {
    return false;
  }

  return stopHooks.some((entry) => hookContainsNotificationScript(entry));
}

export function installNotificationSystem(): void {
  const home = getHomeDir();
  const claudeDir = join(home, '.claude');
  const hooksDir = join(claudeDir, 'hooks');
  const scriptPath = join(hooksDir, 'notify-local-tts.sh');
  const settingsPath = join(claudeDir, 'settings.json');
  const claudeMdPath = join(claudeDir, 'CLAUDE.md');

  mkdirSync(hooksDir, { recursive: true });
  writeFileSync(scriptPath, NOTIFICATION_SCRIPT, 'utf8');
  chmodSync(scriptPath, 0o755);

  const settings = readSettingsOrDefault(settingsPath);

  const hooksValue = settings.hooks;
  const hooks: Record<string, unknown> =
    hooksValue && typeof hooksValue === 'object' && !Array.isArray(hooksValue)
      ? (hooksValue as Record<string, unknown>)
      : {};

  const stopValue = hooks.Stop;
  const stopHooks: unknown[] = Array.isArray(stopValue) ? [...stopValue] : [];

  const alreadyInstalled = stopHooks.some((entry) => hookContainsNotificationScript(entry));

  if (!alreadyInstalled) {
    stopHooks.push({
      matcher: '',
      hooks: [
        {
          type: 'command',
          command: scriptPath,
          async: true,
        },
      ],
    });
  }

  hooks.Stop = stopHooks;
  settings.hooks = hooks;

  writeFileSync(settingsPath, `${JSON.stringify(settings, null, 2)}\n`, 'utf8');

  const currentClaudeMd = existsSync(claudeMdPath) ? readFileSync(claudeMdPath, 'utf8') : '';
  if (!currentClaudeMd.includes('## Voice Notifications')) {
    writeFileSync(claudeMdPath, `${currentClaudeMd}${CLAUDE_MD_VOICE_SECTION}`, 'utf8');
  }
}

export function uninstallNotificationSystem(): void {
  const home = getHomeDir();
  const claudeDir = join(home, '.claude');
  const scriptPath = join(claudeDir, 'hooks', 'notify-local-tts.sh');
  const settingsPath = join(claudeDir, 'settings.json');
  const claudeMdPath = join(claudeDir, 'CLAUDE.md');

  if (existsSync(settingsPath)) {
    const settings = readSettingsOrDefault(settingsPath);
    const hooks = settings.hooks;

    if (hooks && typeof hooks === 'object' && !Array.isArray(hooks)) {
      const hooksObj = hooks as Record<string, unknown>;
      if (Array.isArray(hooksObj.Stop)) {
        hooksObj.Stop = hooksObj.Stop.filter((entry) => !hookContainsNotificationScript(entry));
      }
      settings.hooks = hooksObj;
    }

    writeFileSync(settingsPath, `${JSON.stringify(settings, null, 2)}\n`, 'utf8');
  }

  if (existsSync(claudeMdPath)) {
    const content = readFileSync(claudeMdPath, 'utf8');
    const sectionStart = '## Voice Notifications';
    const startIdx = content.indexOf(sectionStart);

    if (startIdx >= 0) {
      const afterSection = content.slice(startIdx + sectionStart.length);
      const nextHeadingOffset = afterSection.indexOf('\n## ');
      const endIdx = nextHeadingOffset >= 0
        ? startIdx + sectionStart.length + nextHeadingOffset
        : content.length;

      let actualStart = startIdx;
      for (let i = startIdx - 1; i >= 0; i -= 1) {
        if (content[i] !== '\n') {
          actualStart = i + 1;
          break;
        }
        if (i === 0) {
          actualStart = 0;
        }
      }

      const newContent = `${content.slice(0, actualStart)}${content.slice(endIdx)}`;
      writeFileSync(claudeMdPath, newContent, 'utf8');
    }
  }

  if (existsSync(scriptPath)) {
    rmSync(scriptPath, { force: true });
  }
}

export function checkBellMode(): boolean {
  const scriptPath = join(getHomeDir(), '.claude', 'hooks', 'notify-local-tts.sh');
  if (!existsSync(scriptPath)) {
    return false;
  }

  const content = readFileSync(scriptPath, 'utf8');
  return content.includes('afplay') && !content.includes('say "$SUMMARY"');
}

export function setBellMode(enabled: boolean): void {
  const scriptPath = join(getHomeDir(), '.claude', 'hooks', 'notify-local-tts.sh');
  if (!existsSync(scriptPath)) {
    throw new Error('Notification system not installed');
  }

  writeFileSync(scriptPath, enabled ? NOTIFICATION_SCRIPT_BELL : NOTIFICATION_SCRIPT, 'utf8');
  chmodSync(scriptPath, 0o755);
}

export function writeDebugLog(content: string): string {
  const path = '/tmp/agent-manager-x-debug.log';
  writeFileSync(path, content, 'utf8');
  return path;
}
