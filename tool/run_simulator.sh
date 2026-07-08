#!/bin/bash
# Chạy YogaMirror trên iOS Simulator (không ML Kit).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "▶ Chuẩn bị bản Simulator (bỏ ML Kit)..."
cp pubspec.yaml pubspec.yaml.device.bak
grep -v 'google_mlkit' pubspec.yaml.device.bak > pubspec.yaml

flutter pub get
(cd ios && pod install)

echo "▶ Mở iOS Simulator..."
open -a Simulator
sleep 6

echo "▶ Build & chạy trên iPhone Simulator..."
flutter run -d "iPhone 17 Pro" -t lib/main_simulator.dart

echo "▶ Khôi phục pubspec device..."
mv pubspec.yaml.device.bak pubspec.yaml
flutter pub get
(cd ios && pod install)