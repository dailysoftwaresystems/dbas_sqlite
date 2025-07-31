#!/bin/bash
set -e

pod lib lint dbas_sqlite_flutter.podspec --verbose

xcodebuild -workspace TestApp.xcworkspace \
  -scheme TestApp \
  -sdk iphoneos \
  -configuration Release \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
  SKIP_INSTALL=NO \
  BUILD_DIR=build