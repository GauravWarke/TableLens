#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
command -v xcodegen >/dev/null || { echo "Install XcodeGen with brew install xcodegen"; exit 1; }
xcrun --sdk xros --show-sdk-version
mkdir -p Resources Generated
model=Resources/TableObjects.mlmodel
digest=0e32f297ad9cfc0ea8e67276867956488c7ee10dc87c057da4debc939e20b76d
verify() { echo "$digest  $1" | shasum -a 256 -c - >/dev/null 2>&1; }
if ! verify "$model"; then
    tmp=$(mktemp Resources/model.XXXXXX)
    trap 'rm -f "$tmp"' EXIT
    curl --fail --location --retry 2 --output "$tmp" 'https://huggingface.co/apple/coreml-YOLOv3/resolve/63316bf5bf817553ba9426fcac0a306a1b2ddc44/YOLOv3Int8LUT.mlmodel'
    verify "$tmp" || { echo "Detector checksum mismatch"; exit 1; }
    mv "$tmp" "$model"
fi
xcodegen generate
