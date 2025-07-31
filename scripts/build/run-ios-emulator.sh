#!/bin/bash
set -e

cd "$(dirname "$0")/../../example"

flutter run -d "iPhone 16 Plus" --project-root=example