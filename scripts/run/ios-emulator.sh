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
rm -rf ios/Pods ios/Podfile.lock ios/Runner.xcworkspace
flutter pub get
pod install --project-directory=ios
flutter run -d "iPhone 17 Pro Max"
cd "$dir"