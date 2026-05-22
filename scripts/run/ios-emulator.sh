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
flutter pub get
flutter run -d "iPhone 17 Pro Max"
cd "$dir"
