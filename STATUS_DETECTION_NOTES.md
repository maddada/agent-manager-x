# Session Status Detection Notes

Date: 2026-02-14

## Goal

Fix false "Waiting" status in the mini viewer when Codex is still actively running (for example during planning/reasoning).

## What Changed (Codex)

Files:
- `App/Sources/Services/Session/CodexSessionDetector.swift`
- `App/Sources/Services/Session/SessionParsingSupport.swift`

Implementation summary:
- Extended `CodexSessionFile` with:
  - `hasPendingTask: Bool`
  - `lastTaskSignalAt: Date?`
- Added Codex event-driven parsing in `parseCodexSessionFile(...)`:
  - Tracks lifecycle signals from `event_msg` payload types:
    - `user_message`
    - `task_started`
    - `task_complete`
    - `agent_reasoning`
    - `agent_message`
  - Tracks execution signals from `response_item` payload types:
    - `function_call`
    - `function_call_output`
    - `reasoning`
- Derives `hasPendingTask` by comparing latest task trigger (`task_started` or `user_message`) against `task_complete`.
- Updates status inference in `determineCodexStatus(...)`:
  - If `hasPendingTask` and recent task signal (<= 3 minutes), return `.processing`.
  - Falls back to CPU and existing waiting/idle/stale behavior.
  - Keeps old role-based handling but limits `lastRole == "user"` to recent activity (<= 60s) to avoid sticky processing.

## Why This Fix Works

Before:
- Codex status mostly depended on CPU and `lastRole`.
- Active "planning" periods can have low CPU and non-user `lastRole`, so they were classified as `.waiting`.

After:
- Runtime event stream drives active-state detection directly.
- Ongoing reasoning/tool activity is recognized as pending/active work and shown as `.processing`.

## Validation

Command:
- `xcodebuild -project AgentManagerX.xcodeproj -scheme AgentManagerX -configuration Debug -sdk macosx CODE_SIGNING_ALLOWED=NO build`

Result:
- `BUILD SUCCEEDED`

## Rollout Pattern For Claude/OpenCode

Use the same model:
1. Parse explicit lifecycle events (`task_started`, `task_complete`, agent activity).
2. Derive `hasPendingTask` from latest trigger vs completion.
3. Use event-driven pending signal as primary status source.
4. Keep CPU/time heuristics as fallback only.
5. Add recency windows to prevent stale sessions from appearing active forever.

## Additional Changes (Claude + OpenCode)

Date: 2026-02-14 (same follow-up)

### Claude

Files:
- `App/Sources/Services/Session/SessionParsingSupport.swift`
- `App/Sources/Services/Session/ClaudeSessionDetector.swift`

What changed:
- Extended `ClaudeMessageData` with:
  - `hasPendingTask: Bool`
  - `lastTaskSignalAt: String?`
- `parseClaudeMessageData(...)` now parses recent lifecycle/activity lines (last 250 JSONL entries), including:
  - user prompts vs user `tool_result`
  - assistant `thinking` / `tool_use`
  - `progress` records
  - `system` stop/complete-style records
- It computes:
  - latest task start
  - latest task completion
  - latest task signal timestamp
  - pending state (`start > completion`)
- `ClaudeSessionDetector` now promotes status to `.processing` when pending task activity is recent (<= 3 minutes), then falls back to existing Claude heuristics.

### OpenCode

File:
- `App/Sources/Services/Session/OpenCodeSessionDetector.swift`

What changed:
- Added part-aware message state parsing (`OpenCodeMessageState`) from message `part/` records.
- Status logic now considers event-like part signals from newest message:
  - `step-start`
  - `step-finish`
  - `tool`
  - `reasoning`
- `lastMessageForOpenCodeSession(...)` now returns:
  - message role + preview text
  - `hasPendingTask`
  - `lastTaskSignalMs`
- Pending detection rules:
  - newest message is user => pending
  - newest assistant message has active step/tool/reasoning without finish => pending
  - fallback: latest user prompt newer than latest assistant completion => pending
- `determineOpenCodeStatus(...)` now prioritizes pending activity (<= 3 minutes => `.processing`), then uses CPU/age fallback.

## Validation (After Claude + OpenCode)

Command:
- `xcodebuild -project AgentManagerX.xcodeproj -scheme AgentManagerX -configuration Debug -sdk macosx CODE_SIGNING_ALLOWED=NO build`

Result:
- `BUILD SUCCEEDED`

## Follow-up Fix: Claude `/clear` False Processing + Empty Preview

Date: 2026-02-14 (same follow-up)

Files:
- `App/Sources/Services/Session/SessionParsingSupport.swift`
- `App/Resources/native-mini-viewer/MiniViewer.swift`

Issue:
- Claude local-command payloads (for example `/clear` output wrappers like `<local-command-stdout>...</local-command-stdout>`) were being interpreted as normal user/task activity.
- This caused `hasPendingTask` to stay true and made sessions appear as `.processing` even when idle.
- The same payload text could show in mini viewer preview.

What changed:
- Added local-command metadata detection (`<command-name>`, `<command-message>`, `<command-args>`, `<local-command-*>`).
- Excluded those payloads from Claude pending-task lifecycle tracking.
- Treated those payloads as suppressible preview text.
- Updated mini viewer fallback text to `No session message yet`.
- Added mini viewer guard to hide non-displayable placeholder payloads even if one slips through.

Expected behavior now:
- After `/clear`, Claude sessions should settle to waiting/idle instead of sticky processing.
- Mini viewer should show fallback text instead of raw local-command XML-like tags when there is no displayable message.

## Follow-up Fix: Codex Esc Interrupt Sticky Processing

Date: 2026-02-14 (same follow-up)

Files:
- `App/Sources/Services/Session/SessionParsingSupport.swift`
- `App/Sources/Services/Session/CodexSessionDetector.swift`

Issue:
- When Codex was interrupted with Esc while processing, sessions could stay in `.processing` even though work had stopped.
- Root cause: parser only treated `task_complete` as a terminal event, while real Codex logs also emit `turn_aborted` and `thread_rolled_back` during interrupt flow.

What changed:
- Extended `CodexSessionFile` with:
  - `lastInterruptAt: Date?`
  - `lastTerminalEventAt: Date?`
- Codex parser now treats these `event_msg` types as terminal signals:
  - `task_complete`
  - `turn_aborted`
  - `thread_rolled_back`
  - `item_completed` (defensive compatibility)
- Pending-task derivation now compares latest trigger/signal against latest terminal event.
- Status logic now forces immediate `.waiting` after recent interrupt (<= 90s) when there is no newer pending task.

Expected behavior now:
- Pressing Esc mid-processing transitions Codex sessions back to waiting on the next refresh cycle.
- If a new task starts after interrupt, session returns to processing normally.

## Follow-up Fix: Claude Interrupt Sticky Processing

Date: 2026-02-14 (same follow-up)

Files:
- `App/Sources/Services/Session/SessionParsingSupport.swift`

Issue:
- In Claude sessions, `[Request interrupted by user]` could be parsed as a fresh user task start.
- Then pending-task promotion in `ClaudeSessionDetector` could incorrectly force status back to `.processing`.

What changed:
- In `parseClaudeMessageData(...)`, user entries flagged by `isInterruptedRequest(...)` are now treated as terminal events, not new task starts.
- Added a shared completion marker within the parser pass so interrupts update the task-completed boundary used by pending-task derivation.
- Assistant visible output and stop/complete system entries now use the same completion marker path.

Expected behavior now:
- After interrupting Claude mid-run, session status should remain waiting (or age to idle/stale) instead of sticking on processing.
