#!/bin/bash
set -e

DEVICE_NAME="iPhone 17 Pro Max"
DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max"
RUNTIME="com.apple.CoreSimulator.SimRuntime.iOS-26-3"

# Check if simulator already exists
if xcrun simctl list devices | grep -q "$DEVICE_NAME"; then
  echo "$DEVICE_NAME simulator already exists."
else
  echo "Creating $DEVICE_NAME simulator..."
  xcrun simctl create "$DEVICE_NAME" "$DEVICE_TYPE" "$RUNTIME"
  echo "$DEVICE_NAME simulator created."
fi

echo "Booting $DEVICE_NAME..."
xcrun simctl boot "$DEVICE_NAME" 2>/dev/null || true
open -a Simulator
echo "$DEVICE_NAME is ready."
