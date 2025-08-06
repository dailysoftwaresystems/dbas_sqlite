#!/bin/bash
set -e

if [[ " $@ " =~ " --force-head " ]]; then
  echo "Forcing HEAD reset and pull"
  git reset --hard
  git pull
fi

dir=$(dirname "$0")
cd "$dir/../../example"

flutter clean
rm -rf ios/Pods ios/Podfile.lock ios/Runner.xcworkspace
flutter pub get
pod install --project-directory=ios
flutter run -d "iPhone 16 Plus" --project-root=example
cd "$dir"