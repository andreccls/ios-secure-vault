# Requires full Xcode 26 (not only Command Line Tools) and XcodeGen (`brew install xcodegen`).
export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
UDID ?= 32490A14-20D8-49F0-9F26-A5437BAE6AD6
DEST := platform=iOS Simulator,id=$(UDID)
DD ?= build
BUNDLE := dev.andrecoura.SecureVault
APP := $(DD)/Build/Products/Debug-iphonesimulator/SecureVault.app
XCB := xcodebuild -project SecureVault.xcodeproj -derivedDataPath $(DD) -destination '$(DEST)' CODE_SIGNING_ALLOWED=NO -quiet

.PHONY: help project build test test-package test-unit test-ui lint format coverage run screenshots clean
help:
	@grep -E '^\.PHONY' Makefile >/dev/null; echo "build test test-package test-unit test-ui lint format coverage run screenshots clean"

project:
	xcodegen generate

build: project
	$(XCB) -scheme SecureVault build

test-package:
	swift test --package-path VaultCore

test-unit: project
	$(XCB) -scheme SecureVaultUnit -enableCodeCoverage YES -resultBundlePath $(DD)/unit.xcresult test

test-ui: project
	$(XCB) -scheme SecureVault -only-testing:SecureVaultUITests test

# Package tests + app unit tests (simulator). UI tests are separate: `make test-ui`.
test: test-package test-unit

# swift-format ships with the Xcode toolchain: nothing extra to install (ADR 0007).
lint:
	xcrun swift-format lint --strict -r VaultCore/Sources VaultCore/Tests App AppTests AppUITests

format:
	xcrun swift-format format -i -r VaultCore/Sources VaultCore/Tests App AppTests AppUITests

coverage:
	swift test --package-path VaultCore --enable-code-coverage
	xcrun llvm-cov report VaultCore/.build/debug/VaultCorePackageTests.xctest/Contents/MacOS/VaultCorePackageTests \
	  -instr-profile VaultCore/.build/debug/codecov/default.profdata -ignore-filename-regex='Tests|\.build' -use-color=false

run: build
	xcrun simctl boot $(UDID) 2>/dev/null || true
	xcrun simctl install $(UDID) $(APP)
	xcrun simctl launch $(UDID) $(BUNDLE)

# Real screenshots (light + dark) into docs/images. Uses debug-only launch arguments with fictional data.
screenshots: project
	SCREENSHOT_DIR=$(CURDIR)/docs/images/raw ./scripts/screenshots.sh

clean:
	rm -rf build VaultCore/.build SecureVault.xcodeproj
