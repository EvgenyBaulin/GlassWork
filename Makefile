# GlassWork developer commands. Run `make help` for the list.

SHELL := /bin/bash
PROJECT := GlassWork.xcodeproj
SCHEME := GlassWork
DERIVED := build/DerivedData
PACKAGE := Packages/GlassWorkKit
APP := $(DERIVED)/Build/Products/Release/GlassWork.app
SWIFT := xcrun swift
# macOS keeps a widget list per build number, so every commit needs its own.
BUILD_NUMBER := $(shell git rev-list --count HEAD)
XCB := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(DERIVED) -destination 'generic/platform=macOS' CURRENT_PROJECT_VERSION=$(BUILD_NUMBER)

.PHONY: help generate build build-unsigned test test-core snapshots lint format install run clean auto-update-on auto-update-off auto-update-status

help: ## Show this help
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-16s %s\n", $$1, $$2}'

generate: ## Generate GlassWork.xcodeproj from project.yml
	xcodegen generate --quiet

build: generate ## Debug build, signed with the team from Config/Local.xcconfig
	$(XCB) -configuration Debug build -quiet -allowProvisioningUpdates

build-unsigned: generate ## Debug build without code signing (what CI runs)
	$(XCB) -configuration Debug build -quiet CODE_SIGNING_ALLOWED=NO

test-core: ## Fast package tests (core logic and UI snapshots)
	cd $(PACKAGE) && $(SWIFT) test --quiet

test: test-core build-unsigned ## Package tests plus a full app build

snapshots: ## Re-record UI snapshots after an intended visual change
	cd $(PACKAGE) && GW_RECORD_SNAPSHOTS=1 $(SWIFT) test --quiet || true
	cd $(PACKAGE) && $(SWIFT) test --quiet

lint: ## SwiftLint and SwiftFormat checks
	swiftlint lint --quiet --strict
	swiftformat --lint --quiet .

format: ## Format all Swift files
	swiftformat --quiet .

install: generate ## Release build, copy to /Applications and relaunch
	$(XCB) -configuration Release build -quiet -allowProvisioningUpdates
	-pkill -x GlassWork
	rm -rf /Applications/GlassWork.app
	cp -R $(APP) /Applications/
	open /Applications/GlassWork.app

run: build ## Debug build and launch
	-pkill -x GlassWork
	open $(DERIVED)/Build/Products/Debug/GlassWork.app

clean: ## Remove build products
	rm -rf build $(PACKAGE)/.build

auto-update-on: ## Rebuild latest main every 5 days in the background (LaunchAgent)
	scripts/auto-update.sh enable

auto-update-off: ## Turn the background rebuild off
	scripts/auto-update.sh disable

auto-update-status: ## Show background rebuild state and log
	scripts/auto-update.sh status
