#!/usr/bin/env bash
#
# Runs Cupola as the dev identity, com.matthwlabs.cupola.dev: the empty,
# disposable app every agent build on this Mac or a simulator uses (the demo,
# spikes, screenshots, UI checks). The same bundle id on one machine shares
# preferences, keychain and App Group, so production (com.matthwlabs.cupola,
# real connections) and the testlab (com.matthwlabs.cupola.testlab, the lab's
# seed) are never launched to try something. The table of identities lives in
# AGENTS.md (App identities); why, in the wiki's ADR-9.
#
# Usage:
#   scripts/run_dev.sh macos [-- <flutter run args>]
#   scripts/run_dev.sh ios-sim [<simulator udid>] [-- <flutter run args>]
#
# Without a udid, ios-sim uses the simulator named "Cupola Dev", creating and
# booting it when needed.

set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

# The simulator that holds Matt's real connections. A dev build there would
# install beside the house's app and tempt the next agent to reuse it.
HOUSE_SIMULATOR="3275916D-565E-4B49-89A3-D87227209A7F"
# The testlab's own simulator: its tool installs and seeds the testlab app.
TESTLAB_SIMULATOR_NAME="Cupola Testlab"
DEV_SIMULATOR_NAME="Cupola Dev"

DEV_SUFFIX=".dev"
DEV_APP_GROUP="group.com.matthwlabs.cupola.dev"
DEV_KEYCHAIN="com.matthwlabs.cupola.dev"

usage() {
  printf 'Usage: scripts/run_dev.sh macos [-- <flutter run args>]\n' >&2
  printf '       scripts/run_dev.sh ios-sim [<simulator udid>] [-- <flutter run args>]\n' >&2
  exit 1
}

[[ $# -ge 1 ]] || usage
TARGET="$1"
shift

case "$TARGET" in
  macos)
    DEVICE="macos"
    ENTITLEMENTS="Runner/Dev.entitlements"
    # A macOS Keychain access group needs a provisioning profile, which a dev
    # bundle cannot get: the bundle id and the service name are its keychain.
    KEYCHAIN_GROUP=""
    ;;
  ios-sim)
    if [[ $# -ge 1 && "$1" != "--" ]]; then
      DEVICE="$1"
      shift
    else
      DEVICE=$(xcrun simctl list devices | sed -n "s/^ *$DEV_SIMULATOR_NAME (\([0-9A-F-]*\)).*/\1/p" | head -n 1)
      if [[ -z "$DEVICE" ]]; then
        RUNTIME=$(xcrun simctl list runtimes | sed -n 's/^iOS .* - \(com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]*\)$/\1/p' | tail -n 1)
        printf '==> Creating the "%s" simulator (%s)\n' "$DEV_SIMULATOR_NAME" "$RUNTIME"
        DEVICE=$(xcrun simctl create "$DEV_SIMULATOR_NAME" \
          com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro "$RUNTIME")
      fi
    fi
    if [[ "$DEVICE" == "$HOUSE_SIMULATOR" ]]; then
      printf 'Refusing %s: it holds the real connections. Use another simulator.\n' "$DEVICE" >&2
      exit 1
    fi
    SIMULATOR_LINE=$(xcrun simctl list devices | grep "($DEVICE)" || true)
    if [[ -z "$SIMULATOR_LINE" ]]; then
      printf 'Not a simulator on this Mac: %s (a physical iPhone never runs a dev build)\n' "$DEVICE" >&2
      exit 1
    fi
    if [[ "$SIMULATOR_LINE" == *"$TESTLAB_SIMULATOR_NAME ("* ]]; then
      printf 'Refusing %s: it is the testlab'"'"'s simulator.\n' "$DEVICE" >&2
      exit 1
    fi
    if [[ "$SIMULATOR_LINE" != *"(Booted)"* ]]; then
      xcrun simctl boot "$DEVICE"
    fi
    ENTITLEMENTS="Runner/RunnerDev.entitlements"
    KEYCHAIN_GROUP="$DEV_KEYCHAIN"
    ;;
  *)
    usage
    ;;
esac

if [[ $# -ge 1 ]]; then
  [[ "$1" == "--" ]] || usage
  shift
fi

cd "$ROOT_DIR"

# Flutter hands every FLUTTER_XCODE_* variable to xcodebuild as a build
# setting, which beats the production values in the xcconfigs. They reach the
# Runner target alone (see ios/Flutter/Debug.xcconfig and
# macos/Runner/Configs/AppInfo.xcconfig).
export FLUTTER_XCODE_CUPOLA_BUNDLE_SUFFIX="$DEV_SUFFIX"
export FLUTTER_XCODE_CUPOLA_APP_GROUP="$DEV_APP_GROUP"
export FLUTTER_XCODE_CUPOLA_ENTITLEMENTS="$ENTITLEMENTS"
if [[ "$TARGET" == "macos" ]]; then
  # No provisioning profile exists for the dev bundle id, and a sandboxed app
  # cannot be signed without one: the dev Mac app runs outside the sandbox.
  export FLUTTER_XCODE_ENABLE_APP_SANDBOX="NO"
fi

# Flutter rewrites these while it builds (pods, schemes, the lock file). Any
# of them clean before the run is put back after it, so a dev run leaves no
# trace in the tree; a file that was already dirty is never touched.
GENERATED_TRACKED=(
  pubspec.lock
  ios/Podfile
  ios/Podfile.lock
  ios/Runner.xcodeproj/project.pbxproj
  ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme
  macos/Podfile
  macos/Podfile.lock
  macos/Runner.xcodeproj/project.pbxproj
  macos/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme
)
DIRTY_BEFORE=$(git diff --name-only -- "${GENERATED_TRACKED[@]}")

restore_generated() {
  local changed
  changed=$(comm -13 <(printf '%s\n' "$DIRTY_BEFORE" | sort) \
    <(git diff --name-only -- "${GENERATED_TRACKED[@]}" | sort))
  if [[ -n "$changed" ]]; then
    printf '==> Restoring files the build rewrote:\n%s\n' "$changed"
    # shellcheck disable=SC2086
    git checkout -- $changed
  fi
}
trap restore_generated EXIT
# A signal must still reach the EXIT trap, which bash skips on an untrapped one.
trap 'exit 130' INT TERM

# The keychain defines still carry the testlab's names: the testlab task owns
# them and renames them when it ends. Here they give the dev build its own
# keychain service (lib/features/settings/data/settings_service.dart).
flutter run -d "$DEVICE" \
  "--dart-define=CUPOLA_TESTLAB_KEYCHAIN_SERVICE=$DEV_KEYCHAIN" \
  "--dart-define=CUPOLA_TESTLAB_KEYCHAIN_GROUP=$KEYCHAIN_GROUP" \
  "$@"
