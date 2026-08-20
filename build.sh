#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h}"
source_file="$project_dir/Source/MidnightFireworksView.m"
output_dir="$project_dir/dist"
temporary_dir="$(mktemp -d)"
temporary_bundle="$temporary_dir/午前二時の花火.saver"
output_bundle="$output_dir/午前二時の花火.saver"

cleanup() {
    rm -rf "$temporary_dir"
}
trap cleanup EXIT

mkdir -p "$temporary_bundle/Contents/MacOS" "$temporary_bundle/Contents/Resources/Audio" "$output_dir"
cp "$project_dir/Info.plist" "$temporary_bundle/Contents/Info.plist"
cp "$project_dir/Resources/Audio/"*.wav "$temporary_bundle/Contents/Resources/Audio/"

xcrun clang \
    -fobjc-arc \
    -fmodules \
    -bundle \
    -arch arm64 \
    -arch x86_64 \
    -mmacosx-version-min=11.0 \
    -framework AppKit \
    -framework AVFoundation \
    -framework ScreenSaver \
    "$source_file" \
    -o "$temporary_bundle/Contents/MacOS/MidnightFireworksScreensaver"

ditto "$temporary_bundle" "$output_bundle"
codesign --force --deep --sign - "$output_bundle"
codesign --verify --deep --strict "$output_bundle"
echo "$output_bundle"
