#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-"$ROOT_DIR/DerivedData"}"
# Always use this build: only Debug supports isolated duration preferences.
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/dsmn.app"
APP_PID=""
TEST_DIR="$(mktemp -d /tmp/dsmn-menu-e2e.XXXXXX)"
PREFERENCE_SUITE="com.nomdelasociete.dsmn.e2e.$(uuidgen)"
INSTALLED_PID="$(pgrep -f '^/Applications/dsmn.app/Contents/MacOS/dsmn$' || true)"

cleanup() {
  if [[ -n "$APP_PID" ]]; then
    kill "$APP_PID" >/dev/null 2>&1 || true
    wait "$APP_PID" 2>/dev/null || true
  fi
  if [[ -n "$INSTALLED_PID" ]]; then
    open /Applications/dsmn.app
  fi
  rm -rf "$TEST_DIR"
  defaults delete "$PREFERENCE_SUITE" >/dev/null 2>&1 || true
}
trap cleanup EXIT

cd "$ROOT_DIR"
xcodegen generate --use-cache
xcodebuild -project dsmn.xcodeproj -scheme dsmn -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath "$DERIVED_DATA_PATH" build

current_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")"
swiftc "$ROOT_DIR/scripts/click_status_item.swift" -o "$TEST_DIR/click-status-item"
defaults write "$PREFERENCE_SUITE" lastCustomMinutes -int 125
LIVE_MINUTES="0"
if [[ "${E2E_TEST_LIVE_TIMER:-0}" == "1" ]]; then
  "$APP_PATH/Contents/Library/Helpers/dsmnctl" status --json > "$TEST_DIR/before.json"
  # A valid submission must not shorten the user's existing protection. Opt-in
  # integration testing rounds its current remaining duration up to the minute.
  LIVE_MINUTES="$(python3 - "$TEST_DIR/before.json" <<'PY'
import json, math, sys
r = json.load(open(sys.argv[1]))
assert r['state']['ownsSleepDisable'] and r['decision']['shouldPreventSleep'], 'Live test requires existing helper protection'
assert r['snapshot'].get('lidClosed') is False, 'Live test requires an open lid'
m = math.ceil(r['manualRemainingSeconds'] / 60)
assert 1 <= m <= 480
print(m)
PY
)"
fi
# Process-only overrides preserve preferences. Avoid duplicate bundle IDs during AX testing.
if [[ -n "$INSTALLED_PID" ]]; then kill "$INSTALLED_PID"; fi
DSMN_DURATION_TEST_SUITE="$PREFERENCE_SUITE" "$APP_PATH/Contents/MacOS/dsmn" -onboardingWizardDismissed YES \
  -deferredHelperUpdateBuild "$current_build" -setupRemindersSuppressed YES >/dev/null 2>&1 &
APP_PID="$!"

cat > "$TEST_DIR/driver.applescript" <<'APPLESCRIPT'
on openStatusItem(statusItem, clickTool)
    tell application "System Events"
        set itemPosition to position of statusItem
        set itemSize to size of statusItem
    end tell
    set clickX to round ((item 1 of itemPosition) + (item 1 of itemSize) / 2)
    set clickY to round ((item 2 of itemPosition) + (item 2 of itemSize) / 2)
    do shell script (quoted form of clickTool) & " " & clickX & " " & clickY
end openStatusItem

on firstElementIdentified(elementIdentifier, containerElement)
    tell application "System Events"
        repeat with currentElement in (UI elements of containerElement)
            try
                if value of attribute "AXIdentifier" of currentElement is elementIdentifier then return currentElement
            end try
            try
                set nestedElement to my firstElementIdentified(elementIdentifier, currentElement)
                if nestedElement is not missing value then return nestedElement
            end try
        end repeat
    end tell
    return missing value
end firstElementIdentified

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

on openPanel(targetProcess, statusItem, clickTool)
    tell application "System Events"
        repeat with currentWindow in windows of targetProcess
            if my firstButtonIdentified("panel.custom-duration", currentWindow) is not missing value then return currentWindow
        end repeat
    end tell
    -- A relaunched status item can still be moving into place when AX exposes it.
    repeat 2 times
        delay 0.3
        my openStatusItem(statusItem, clickTool)
        tell application "System Events"
            repeat 60 times
                repeat with currentWindow in windows of targetProcess
                    if my firstButtonIdentified("panel.custom-duration", currentWindow) is not missing value then return currentWindow
                end repeat
                delay 0.1
            end repeat
        end tell
    end repeat
    error "Status-item click did not open the timer panel."
end openPanel

on fillField(fieldElement, fieldText)
    tell application "System Events"
        set value of attribute "AXFocused" of fieldElement to true
        keystroke "a" using command down
        keystroke fieldText
        if value of fieldElement is not fieldText then error "Text input did not reach the intended field."
    end tell
end fillField

on run arguments
    set targetPID to (item 1 of arguments) as integer
    set clickTool to item 2 of arguments
    set liveMinutes to (item 3 of arguments) as integer
    set verifyReload to (item 4 of arguments) is "reload"
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
        set panelWindow to my openPanel(targetProcess, statusItem, clickTool)
        if verifyReload then
            repeat with presetMinutes in {15, 60, 120, 480}
                if my firstButtonIdentified("panel.preset." & presetMinutes, panelWindow) is missing value then error "Preset lost after app restart."
            end repeat
            click my firstButtonIdentified("panel.custom-duration", panelWindow)
            delay 0.3
            set durationWindow to window "Keep Awake" of targetProcess
            set expectedMinutes to 125
            if liveMinutes > 0 then set expectedMinutes to liveMinutes
            set hoursField to my firstElementIdentified("duration.hours", durationWindow)
            set minutesField to my firstElementIdentified("duration.minutes", durationWindow)
            if value of hoursField is not ((expectedMinutes div 60) as text) or value of minutesField is not ((expectedMinutes mod 60) as text) then error "Custom duration lost after app restart."
            click my firstButtonIdentified("duration.cancel", durationWindow)
            return "e2e presets and custom duration survive app restart"
        end if
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
        if setupButton is missing value then
            log ("Status item position: " & (position of statusItem as text))
            log ("App windows: " & (name of windows of targetProcess as text))
            error "Compact panel is missing Setup & Troubleshooting."
        end if
        if stopButton is missing value then error "Compact panel is missing Stop."
        if enabled of stopButton is false then error "Stop must remain available."

        -- Invalid input must stay in Custom and must not issue a real timer command.
        set customButton to missing value
        repeat with currentWindow in windows of targetProcess
            set customButton to my firstButtonIdentified("panel.custom-duration", currentWindow)
            if customButton is not missing value then exit repeat
        end repeat
        if customButton is missing value then error "Compact panel is missing Custom."
        click customButton
        repeat 40 times
            if exists window "Keep Awake" of targetProcess then exit repeat
            delay 0.1
        end repeat
        set durationWindow to window "Keep Awake" of targetProcess
        set hoursField to my firstElementIdentified("duration.hours", durationWindow)
        set minutesField to my firstElementIdentified("duration.minutes", durationWindow)
        if value of hoursField is not "2" then error "Custom did not restore saved hours."
        if value of minutesField is not "5" then error "Custom did not restore saved minutes."
        my fillField(hoursField, "8")
        my fillField(minutesField, "1")
        if value of hoursField is not "8" or value of minutesField is not "1" then error "Custom input automation did not enter 8h01; refusing to submit."
        click my firstButtonIdentified("duration.submit", durationWindow)
        delay 0.3
        if not (exists window "Keep Awake" of targetProcess) then error "Invalid duration dismissed Custom."
        if my firstElementIdentified("duration.error", durationWindow) is missing value then error "Invalid duration has no visible error."
        if liveMinutes > 0 then
            my fillField(hoursField, ((liveMinutes div 60) as text))
            my fillField(minutesField, ((liveMinutes mod 60) as text))
            -- Exercise the default keyboard action, including field commit.
            key code 36
            repeat 80 times
                if not (exists window "Keep Awake" of targetProcess) then exit repeat
                delay 0.1
            end repeat
            if exists window "Keep Awake" of targetProcess then error "Valid custom duration was not confirmed."
        else
            click my firstButtonIdentified("duration.cancel", durationWindow)
        end if
        delay 0.2
        if exists window "Keep Awake" of targetProcess then error "Custom did not close."
        set panelWindow to my openPanel(targetProcess, statusItem, clickTool)
        set setupButton to my firstButtonIdentified("panel.setup", panelWindow)
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

        set presetsField to my firstElementIdentified("settings.duration-presets", setupWindow)
        if presetsField is missing value then error "Settings are missing timer presets."
        my fillField(presetsField, "12h")
        click my firstButtonIdentified("settings.save-duration-presets", setupWindow)
        delay 0.2
        set feedback to my firstElementIdentified("settings.duration-feedback", setupWindow)
        if value of feedback does not contain "Invalid duration" then error "Invalid presets were not rejected."
        my fillField(presetsField, "15m, 1h, 2h, 8h")
        click my firstButtonIdentified("settings.save-duration-presets", setupWindow)
        delay 0.2
        set feedback to my firstElementIdentified("settings.duration-feedback", setupWindow)
        if value of feedback does not contain "Saved" then error "Valid presets were not saved."
        click my firstButtonIdentified("setup.done", setupWindow)
        set panelWindow to my openPanel(targetProcess, statusItem, clickTool)
        set customButton to my firstButtonIdentified("panel.custom-duration", panelWindow)
        if customButton is missing value then error "Could not reopen updated preset menu."
        -- Labels come from the saved durations, not the old hard-coded buttons.
        repeat with presetMinutes in {15, 60, 120, 480}
            if my firstButtonIdentified("panel.preset." & presetMinutes, panelWindow) is missing value then error "Saved preset missing from menu: " & presetMinutes
        end repeat
        click customButton
        delay 0.3
        set durationWindow to window "Keep Awake" of targetProcess
        set hoursField to my firstElementIdentified("duration.hours", durationWindow)
        set minutesField to my firstElementIdentified("duration.minutes", durationWindow)
        if liveMinutes > 0 then
            if value of hoursField is not ((liveMinutes div 60) as text) then error "Last successful custom hours were not restored."
            if value of minutesField is not ((liveMinutes mod 60) as text) then error "Last successful custom minutes were not restored."
        else
            if value of hoursField is not "2" or value of minutesField is not "5" then error "Invalid input overwrote the saved custom duration."
        end if
        click radio button 2 of radio group 1 of group 1 of durationWindow
        if value of radio button 2 of radio group 1 of group 1 of durationWindow is not 1 then error "Add time was not selected."
        my fillField(hoursField, "8")
        my fillField(minutesField, "1")
        click my firstButtonIdentified("duration.submit", durationWindow)
        delay 0.2
        if my firstElementIdentified("duration.error", durationWindow) is missing value then error "Add did not validate its duration."
        if liveMinutes > 0 then
            -- An active lease plus eight hours must be rejected, never replaced.
            my fillField(minutesField, "0")
            click my firstButtonIdentified("duration.submit", durationWindow)
            repeat 80 times
                if my firstElementIdentified("duration.error", durationWindow) is not missing value then exit repeat
                delay 0.1
            end repeat
            set addError to my firstElementIdentified("duration.error", durationWindow)
            if addError is missing value then error "Add beyond the limit was not rejected."
            set errorText to value of addError
            if errorText does not contain "Update Helper" and errorText does not contain "480" and errorText does not contain "8h" then error "Unexpected Add error: " & errorText
        end if
        click my firstButtonIdentified("duration.cancel", durationWindow)
    end tell
end run
APPLESCRIPT

osascript "$TEST_DIR/driver.applescript" "$APP_PID" "$TEST_DIR/click-status-item" "$LIVE_MINUTES" exercise
kill "$APP_PID"
wait "$APP_PID" 2>/dev/null || true
DSMN_DURATION_TEST_SUITE="$PREFERENCE_SUITE" "$APP_PATH/Contents/MacOS/dsmn" -onboardingWizardDismissed YES \
  -deferredHelperUpdateBuild "$current_build" -setupRemindersSuppressed YES >/dev/null 2>&1 &
APP_PID="$!"
osascript "$TEST_DIR/driver.applescript" "$APP_PID" "$TEST_DIR/click-status-item" "$LIVE_MINUTES" reload

if [[ "$LIVE_MINUTES" != "0" ]]; then
  "$APP_PATH/Contents/Library/Helpers/dsmnctl" status --json > "$TEST_DIR/after.json"
  python3 - "$TEST_DIR/before.json" "$TEST_DIR/after.json" <<'PY'
import json, sys
before, after = [json.load(open(p)) for p in sys.argv[1:]]
assert after['state']['ownsSleepDisable'] and after['decision']['shouldPreventSleep']
assert after['state']['manualUntil'] >= before['state']['manualUntil'], 'Test shortened live protection'
print('e2e live custom submission confirmed by helper; prior deadline preserved')
PY
fi

echo "e2e compact panel and setup passed"
