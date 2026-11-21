#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
bash Prepare.command
mode=${1:-standard}
case "$mode" in standard|live) ;; *) echo "Use standard or live"; exit 2;; esac
read -r -p "Signing team ID: " team
[[ "$team" =~ ^[A-Za-z0-9]{10}$ ]] || { echo "Expected a 10-character team ID"; exit 2; }
bundle="app.tablelens.t${team}.prototype"
extra=()
if [[ "$mode" == live ]]; then
    read -r -p "Apple-approved bundle ID for Main Camera Access: " bundle
    [[ -n "$bundle" && "$bundle" != *" "* ]] || exit 2
    extra+=("SWIFT_ACTIVE_COMPILATION_CONDITIONS=LIVE_CAMERA" "CODE_SIGN_ENTITLEMENTS=Camera.entitlements")
fi
xcrun devicectl list devices
read -r -p "Paired Vision Pro identifier: " device
[[ -n "$device" ]] || exit 2
xcodebuild -project TableLens.xcodeproj -scheme TableLens -configuration Debug \
    -destination 'generic/platform=visionOS' -derivedDataPath ".build/$mode" -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$team" PRODUCT_BUNDLE_IDENTIFIER="$bundle" CODE_SIGN_STYLE=Automatic \
    ${extra[@]+"${extra[@]}"} build
app=".build/$mode/Build/Products/Debug-xros/TableLens.app"
xcrun devicectl device install app --device "$device" "$app"
xcrun devicectl device process launch --device "$device" "$bundle"
