#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-"$ROOT_DIR/DerivedData"}"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/dsmn.app"
DEFAULTS_DOMAIN="com.nomdelasociete.dsmn"
WIZARD_DISMISSED_KEY="onboardingWizardDismissed"
DEFERRED_HELPER_UPDATE_KEY="deferredHelperUpdateBuild"
WIZARD_DISMISSED_EXISTED=0
WIZARD_DISMISSED_VALUE=""
DEFERRED_HELPER_UPDATE_EXISTED=0
DEFERRED_HELPER_UPDATE_VALUE=""
WAS_RUNNING=0
APP_PID=""

if pgrep -x dsmn >/dev/null 2>&1; then
  WAS_RUNNING=1
fi

if WIZARD_DISMISSED_VALUE="$(defaults read "$DEFAULTS_DOMAIN" "$WIZARD_DISMISSED_KEY" 2>/dev/null)"; then
  WIZARD_DISMISSED_EXISTED=1
fi

if DEFERRED_HELPER_UPDATE_VALUE="$(defaults read "$DEFAULTS_DOMAIN" "$DEFERRED_HELPER_UPDATE_KEY" 2>/dev/null)"; then
  DEFERRED_HELPER_UPDATE_EXISTED=1
fi

restore_bool_default() {
  local key="$1"
  local existed="$2"
  local value="$3"

  if [ "$existed" = "1" ]; then
    case "$value" in
      1|true|TRUE)
        defaults write "$DEFAULTS_DOMAIN" "$key" -bool true >/dev/null
        ;;
      0|false|FALSE)
        defaults write "$DEFAULTS_DOMAIN" "$key" -bool false >/dev/null
        ;;
      *)
        defaults write "$DEFAULTS_DOMAIN" "$key" "$value" >/dev/null
        ;;
    esac
  else
    defaults delete "$DEFAULTS_DOMAIN" "$key" >/dev/null 2>&1 || true
  fi
}

restore_int_default() {
  local key="$1"
  local existed="$2"
  local value="$3"

  if [ "$existed" = "1" ]; then
    defaults write "$DEFAULTS_DOMAIN" "$key" -int "$value" >/dev/null
  else
    defaults delete "$DEFAULTS_DOMAIN" "$key" >/dev/null 2>&1 || true
  fi
}

cleanup() {
  restore_bool_default "$WIZARD_DISMISSED_KEY" "$WIZARD_DISMISSED_EXISTED" "$WIZARD_DISMISSED_VALUE"
  restore_int_default "$DEFERRED_HELPER_UPDATE_KEY" "$DEFERRED_HELPER_UPDATE_EXISTED" "$DEFERRED_HELPER_UPDATE_VALUE"
  if [ -n "$APP_PID" ]; then
    osascript -e 'tell application id "com.nomdelasociete.dsmn" to quit' >/dev/null 2>&1 || true
    for _ in {1..20}; do
      if ! kill -0 "$APP_PID" >/dev/null 2>&1; then
        break
      fi
      sleep 0.1
    done
    if kill -0 "$APP_PID" >/dev/null 2>&1; then
      kill "$APP_PID" >/dev/null 2>&1 || true
    fi
    wait "$APP_PID" 2>/dev/null || true
  fi
  killall dsmn >/dev/null 2>&1 || true
  if [ "$WAS_RUNNING" = "1" ] && [ -d /Applications/dsmn.app ]; then
    open -n /Applications/dsmn.app >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT

cd "$ROOT_DIR"
xcodegen generate --use-cache
xcodebuild \
  -project dsmn.xcodeproj \
  -scheme dsmn \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

current_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")"
defaults write "$DEFAULTS_DOMAIN" "$WIZARD_DISMISSED_KEY" -bool true
defaults write "$DEFAULTS_DOMAIN" "$DEFERRED_HELPER_UPDATE_KEY" -int "$current_build"
killall dsmn >/dev/null 2>&1 || true
"$APP_PATH/Contents/MacOS/dsmn" >/dev/null 2>&1 &
APP_PID="$!"

osascript <<'APPLESCRIPT'
on firstButtonIdentified(buttonIdentifier, containerElement)
    tell application "System Events"
        repeat with currentElement in (UI elements of containerElement)
            try
                if role of currentElement is "AXButton" and value of attribute "AXIdentifier" of currentElement is buttonIdentifier then
                    return currentElement
                end if
            end try

            try
                set nestedButton to my firstButtonIdentified(buttonIdentifier, currentElement)
                if nestedButton is not missing value then
                    return nestedButton
                end if
            end try
        end repeat
    end tell

    return missing value
end firstButtonNamed

tell application "System Events"
    if UI elements enabled is false then
        error "Accessibility automation is not enabled for this shell. Enable it in Privacy & Security > Accessibility, then rerun scripts/e2e_menu_setup.sh."
    end if
end tell

tell application "System Events"
    repeat 60 times
        if exists process "dsmn" then exit repeat
        delay 0.25
    end repeat

    if not (exists process "dsmn") then
        error "dsmn process did not launch"
    end if

    tell process "dsmn"
        set foundSetupItem to false
        set statusMenuItem to missing value

        repeat 60 times
            repeat with currentMenuBar in menu bars
                repeat with currentMenuBarItem in menu bar items of currentMenuBar
                    try
                        if description of currentMenuBarItem is "status menu" then
                            set statusMenuItem to currentMenuBarItem
                            exit repeat
                        end if
                    end try
                end repeat

                if statusMenuItem is not missing value then exit repeat
            end repeat

            if statusMenuItem is not missing value then exit repeat
            delay 0.25
        end repeat

        if statusMenuItem is missing value then
            error "Could not find dsmn's menu bar status item"
        end if

        repeat 20 times
            try
                perform action "AXPress" of statusMenuItem
                delay 0.25

                if exists menu item "Setup & Troubleshooting..." of menu 1 of statusMenuItem then
                    set foundSetupItem to true
                    exit repeat
                end if
            end try

            delay 0.25
        end repeat

        if foundSetupItem is false then
            set menuSummary to ""
            try
                repeat with currentMenuItem in menu items of menu 1 of statusMenuItem
                    try
                        set menuSummary to menuSummary & ((name of currentMenuItem) as text) & linefeed
                    end try
                end repeat
            end try

            error "Could not find the Setup & Troubleshooting menu item. Visible items:" & linefeed & menuSummary
        end if

        if exists window "Setup & Troubleshooting" then
            error "Setup & Troubleshooting window opened before the menu item was clicked"
        end if

        click menu item "Setup & Troubleshooting..." of menu 1 of statusMenuItem

        repeat 60 times
            if exists window "Setup & Troubleshooting" then exit repeat
            delay 0.25
        end repeat

        if not (exists window "Setup & Troubleshooting") then
            error "Setup & Troubleshooting window did not open"
        end if

        tell window "Setup & Troubleshooting"
            set refreshButton to my firstButtonIdentified("setup.refresh", it)
            if refreshButton is missing value then
                error "Setup & Troubleshooting window is missing Refresh"
            end if

            click refreshButton

            set setupGuideButton to my firstButtonIdentified("setup.guide", it)
            if setupGuideButton is missing value then
                error "Setup & Troubleshooting window is missing Setup Guide"
            end if

            set doneButton to my firstButtonIdentified("setup.done", it)
            if doneButton is missing value then
                error "Setup & Troubleshooting window is missing Done"
            end if
        end tell
    end tell
end tell
APPLESCRIPT

echo "e2e menu setup passed"
