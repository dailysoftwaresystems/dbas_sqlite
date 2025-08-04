#!/bin/bash
set -e

flutter clean
flutter pub get
pod install --project-directory=android
flutter run -d "Medium Phone API 35" --project-root=example