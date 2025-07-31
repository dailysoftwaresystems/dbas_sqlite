#!/bin/bash
set -e

cd "$(dirname "$0")/../../example"

flutter clean
rm -rf ios/Pods ios/Podfile.lock ios/Runner.xcworkspace
flutter pub get
pod install --project-directory=ios
flutter run -d "iPhone 16 Plus" --project-root=example