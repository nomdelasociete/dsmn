#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-"$ROOT_DIR/DerivedData"}"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/dsmn.app"
APP_PID=""
INSTALLED_PID="$(pgrep -f '^/Applications/dsmn.app/Contents/MacOS/dsmn$' || true)"

cleanup() {
  if [[ -n "$APP_PID" ]]; then
    kill "$APP_PID" >/dev/null 2>&1 || true
    wait "$APP_PID" 2>/dev/null || true
  fi
  if [[ -n "$INSTALLED_PID" ]]; then
    open /Applications/dsmn.app
  fi
}
trap cleanup EXIT

cd "$ROOT_DIR"
xcodegen generate --use-cache
xcodebuild -project dsmn.xcodeproj -scheme dsmn -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath "$DERIVED_DATA_PATH" build

current_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")"
# Process-only overrides preserve preferences. Avoid duplicate bundle IDs during AX testing.
if [[ -n "$INSTALLED_PID" ]]; then kill "$INSTALLED_PID"; fi
"$APP_PATH/Contents/MacOS/dsmn" -onboardingWizardDismissed YES \
  -deferredHelperUpdateBuild "$current_build" -setupRemindersSuppressed YES >/dev/null 2>&1 &
APP_PID="$!"

osascript - "$APP_PID" <<'APPLESCRIPT'
on firstButtonIdentified(buttonIdentifier, containerElement)
    tell application "System Events"
        repeat with currentElement in (UI elements of containerElement)
            try
                if role of currentElement is "AXButton" and value of attribute "AXIdentifier" of currentElement is buttonIdentifier then return currentElement
            end try
            try
                set nestedButton to my firstButtonIdentified(buttonIdentifier, currentElement)
                if nestedButton is not missing value then return nestedButton
            end try
        end repeat
    end tell
    return missing value
end firstButtonIdentified

on run arguments
    set targetPID to (item 1 of arguments) as integer
    tell application "System Events"
        if UI elements enabled is false then error "Enable Accessibility for this shell before running scripts/e2e_menu_setup.sh."
        repeat 60 times
            if exists (first application process whose unix id is targetPID) then exit repeat
            delay 0.25
        end repeat
        set targetProcess to first application process whose unix id is targetPID
        set frontmost of targetProcess to true

        set statusItem to missing value
        repeat 60 times
            repeat with currentMenuBar in menu bars of targetProcess
                repeat with currentItem in menu bar items of currentMenuBar
                    try
                        if description of currentItem is "status menu" then set statusItem to currentItem
                    end try
                end repeat
            end repeat
            if statusItem is not missing value then exit repeat
            delay 0.25
        end repeat
        if statusItem is missing value then error "Could not find the heartbeat status item."
        perform action "AXPress" of statusItem

        set setupButton to missing value
        set stopButton to missing value
        repeat 60 times
            repeat with currentWindow in windows of targetProcess
                set setupButton to my firstButtonIdentified("panel.setup", currentWindow)
                set stopButton to my firstButtonIdentified("panel.stop", currentWindow)
                if setupButton is not missing value then exit repeat
            end repeat
            if setupButton is not missing value then exit repeat
            delay 0.25
        end repeat
        if setupButton is missing value then error "Compact panel is missing Setup & Troubleshooting."
        if stopButton is missing value then error "Compact panel is missing Stop."
        if enabled of stopButton is false then error "Stop must remain available."
        click setupButton

        repeat 60 times
            if exists window "Setup & Troubleshooting" of targetProcess then exit repeat
            delay 0.25
        end repeat
        if not (exists window "Setup & Troubleshooting" of targetProcess) then error "Setup window did not open."
        set setupWindow to window "Setup & Troubleshooting" of targetProcess
        set refreshButton to my firstButtonIdentified("setup.refresh", setupWindow)
        if refreshButton is missing value then error "Setup window is missing Refresh."
        click refreshButton
        if my firstButtonIdentified("setup.guide", setupWindow) is missing value then error "Setup window is missing Setup Guide."
        if my firstButtonIdentified("setup.done", setupWindow) is missing value then error "Setup window is missing Done."
    end tell
end run
APPLESCRIPT

echo "e2e compact panel and setup passed"
