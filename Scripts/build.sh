#!/bin/sh
# Build Rotonda. Usage: Scripts/build.sh [xcodebuild args...]
# Reads the signing team from team.txt (git-ignored) in the repository root.
# Without team.txt it signs ad hoc, which the simulator accepts and which still embeds the
# App Group entitlement; an unsigned build cannot share data with its widgets.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
# Content is regenerated manually (python3 Scripts/prepare_content.py), not on every build.
if [ ! -f "$root/Rotonda/Resources/patente.db" ]; then
  echo "Missing Rotonda/Resources/patente.db; run: python3 Scripts/prepare_content.py" >&2
  exit 1
fi
destination=${DESTINATION:-generic/platform=iOS Simulator}
if [ -f "$root/team.txt" ]; then
  team=$(tr -d '[:space:]' < "$root/team.txt")
  set -- DEVELOPMENT_TEAM="$team" "$@"
else
  set -- CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= "$@"
fi
exec xcodebuild -project "$root/Rotonda.xcodeproj" -scheme Rotonda \
  -destination "$destination" -derivedDataPath "${DERIVED_DATA:-${TMPDIR:-/tmp}/rotonda-build}" "$@" build
