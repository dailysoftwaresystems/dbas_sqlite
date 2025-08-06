#!/bin/bash
set -e

# Fix UTF-8 encoding issues with CocoaPods
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

if [[ " $@ " =~ " --force-head " ]]; then
  echo "Forcing HEAD reset and pull"
  git reset --hard
  git pull
fi

dir=$(dirname "$0")
cd "$dir/../../example"

flutter clean
rm -rf macos/Pods macos/Podfile.lock macos/Runner.xcworkspace
flutter pub get
pod install --project-directory=macos
flutter run -d "macos" --project-root=example
cd "$dir"