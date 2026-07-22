#!/usr/bin/env bash
set -euo pipefail

if ! command -v flutter >/dev/null 2>&1; then
  echo "Không tìm thấy Flutter SDK trong PATH." >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

flutter create \
  --platforms=android,ios \
  --org com.yogamirror \
  --project-name yoga_mirror_rive_demo \
  "$tmp_dir/yoga_mirror_rive_demo"

rm -rf android ios
cp -R "$tmp_dir/yoga_mirror_rive_demo/android" ./android
cp -R "$tmp_dir/yoga_mirror_rive_demo/ios" ./ios
flutter pub get

printf '\nXong. Kết nối điện thoại rồi chạy: flutter run\n'
