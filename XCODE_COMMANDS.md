```bash
# One-command workflows (like npm scripts)
make dev
make prod

# Open the project in Xcode
open AgentManagerX.xcodeproj

# Quit any running app, then build and launch Debug
osascript -e 'tell application id "com.madda.agentmanagerx" to quit' >/dev/null 2>&1 || true; pkill -x "Agent Manager X" >/dev/null 2>&1 || true; xcodebuild -project AgentManagerX.xcodeproj -scheme AgentManagerX -configuration Debug -derivedDataPath build build && open "build/Build/Products/Debug/Agent Manager X.app"

# Build a Release version (for distribution)
xcodebuild -project AgentManagerX.xcodeproj -scheme AgentManagerX -configuration Release -derivedDataPath build build

# Remove old installed app from /Applications
rm -rf "/Applications/Agent Manager X.app"

# Copy the new Release app into /Applications
cp -R "build/Build/Products/Release/Agent Manager X.app" "/Applications/"
```
