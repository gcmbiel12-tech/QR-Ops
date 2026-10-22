#!/usr/bin/env bash
set -euo pipefail

# Reuse the SDK installed by CI when available. Vercel's native build image does
# not include Flutter, so bootstrap the same pinned stable release there.
FLUTTER_VERSION="3.47.5"
if ! command -v flutter >/dev/null 2>&1; then
  : "${HOME:?HOME must be set to install Flutter}"
  FLUTTER_HOME="${HOME}/.cache/qr-ops/flutter-${FLUTTER_VERSION}"
  if [[ ! -x "${FLUTTER_HOME}/bin/flutter" ]]; then
    mkdir -p "$(dirname "${FLUTTER_HOME}")"
    git clone --depth 1 --branch "${FLUTTER_VERSION}" \
      https://github.com/flutter/flutter.git "${FLUTTER_HOME}"
  fi
  export PATH="${FLUTTER_HOME}/bin:${PATH}"
fi

flutter --version
flutter pub get --enforce-lockfile
flutter build web --release --no-pub
