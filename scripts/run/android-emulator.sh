#!/bin/bash
set -e

flutter clean
flutter pub get
flutter run -d "Medium Phone API 35" --project-root=example
