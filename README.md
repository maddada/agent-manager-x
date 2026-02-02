# Agent Manager X

A macOS desktop app to monitor your Claude Code, Codex, OpenCode AI coding agents in real-time with voice or bell notifications. Easily jump to a conversation in any editor or terminal!

Shows RAM and CPU usage for every running session and lets you code Stale or Idle chats that are wasting memory with 1 click! 

---
**Full credit and huge thanks to [@ozankasikci](https://github.com/ozankasikci) for the idea and initial code.**<br />
**I really liked it and wanted to add so much to it without waiting on approvals hence this fork.**
**Please star his repo here: https://github.com/ozankasikci/agent-sessions**

---

<img width="4281" height="4218" alt="screenshot-with-background-12" src="https://github.com/user-attachments/assets/2787c40e-9c74-41e8-8e37-1396f18f1056" />

---

## Short 3 min Demo of AMX: [Link for mobile](https://github.com/user-attachments/assets/bc051b70-c987-4528-9939-e7a59844cff2)
<video src="https://github.com/user-attachments/assets/bc051b70-c987-4528-9939-e7a59844cff2" width="600" controls></video>


Full video showing the best agentic workflow I found for easily managing 10+ agents
https://youtube.com/watch?v=5LRAKaYJXjw

## Features vs [original repo](https://github.com/ozankasikci/agent-sessions)
(huge credit for the idea, I just took it and made it better, keeping the same license)

- Better reliability when it comes to showing current progress
- Improved UX in a bunch of areas like grouping sessions per project
- Added audio notifications (Summary Text to Speech and Bell modes)
- Implpemented Codex CLI support
- Fix lots of bugs
- Added theming
- Add support for tons of editors
- Added ability to click on a session to jump to it
- Remember last location and size
- Default Editor and Default Terminal Support
- Themes and background image support
- Cleaned up codebase a bunch
- Added close buttons for a project's sessions, for all from specific agent, for all stale sessions, etc.
- Added fading and sorting based on the last activity on each session (5 mins = idle, 10 minutes = stale)
- Coming soon: auto closing for stale sessions to save ram
- Coming soon: stale / idle timing setting

Please ask or do a PR if you have any feature ideas!

## Supported Agents

- **Claude Code** - Anthropic's official CLI for Claude
- **OpenCode** - Open-source AI coding assistant
- **Codex** - OpenAI's coding agent CLI

## Features

- View all active coding agent sessions in one place
- Real-time status detection (Thinking, Processing, Waiting, Idle)
- Global hotkey to toggle visibility (default: `Ctrl+Space`, configurable, I personally use ctrl+shift+cmd+space)
- Click to focus on a specific session's terminal
- Custom session names (rename by right clicking on a session)
- Quick access URL for each session (e.g., dev server links)
