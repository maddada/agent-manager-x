PROJECT := AgentManagerX.xcodeproj
SCHEME := AgentManagerX
BUNDLE_ID := com.madda.agentmanagerx
APP_NAME := Agent Manager X
DERIVED_DATA := build
DEBUG_APP := $(DERIVED_DATA)/Build/Products/Debug/$(APP_NAME).app
RELEASE_APP := $(DERIVED_DATA)/Build/Products/Release/$(APP_NAME).app
INSTALL_DIR := /Applications
INSTALLED_APP := $(INSTALL_DIR)/$(APP_NAME).app

.PHONY: dev prod

dev:
	@osascript -e 'tell application id "$(BUNDLE_ID)" to quit' >/dev/null 2>&1 || true
	@pkill -x "$(APP_NAME)" >/dev/null 2>&1 || true
	xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration Debug -derivedDataPath "$(DERIVED_DATA)" build
	open "$(DEBUG_APP)"

prod:
	@osascript -e 'tell application id "$(BUNDLE_ID)" to quit' >/dev/null 2>&1 || true
	@pkill -x "$(APP_NAME)" >/dev/null 2>&1 || true
	xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration Release -derivedDataPath "$(DERIVED_DATA)" build
	rm -rf "$(INSTALLED_APP)"
	cp -R "$(RELEASE_APP)" "$(INSTALL_DIR)/"
	open "$(INSTALLED_APP)"
