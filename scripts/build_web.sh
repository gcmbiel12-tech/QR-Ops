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

BUILD_DEFINES=()
if [[ -n "${SUPABASE_URL:-}" && -n "${SUPABASE_PUBLISHABLE_KEY:-}" ]]; then
  BUILD_DEFINES+=(
    "--dart-define=SUPABASE_URL=${SUPABASE_URL}"
    "--dart-define=SUPABASE_PUBLISHABLE_KEY=${SUPABASE_PUBLISHABLE_KEY}"
  )
elif [[ -n "${SUPABASE_URL:-}" || -n "${SUPABASE_PUBLISHABLE_KEY:-}" ]]; then
  echo "Error: configure SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY together." >&2
  exit 1
elif [[ "${VERCEL:-}" == "1" ]]; then
  echo "Error: configure SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY for the Vercel build." >&2
  exit 1
else
  echo "Warning: local build without Supabase; remote auth and sync will be unavailable."
fi

flutter build web --release --no-pub "${BUILD_DEFINES[@]}"
