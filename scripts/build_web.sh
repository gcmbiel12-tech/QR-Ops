#!/usr/bin/env bash
set -euo pipefail

# GitHub Actions installs the pinned Flutter SDK before invoking `vercel build`.
# The Vercel CLI receives the resulting static build output.
flutter pub get --enforce-lockfile
flutter build web --release --no-pub
