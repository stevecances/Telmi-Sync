#!/bin/bash
# Installs the Python runtime used by Piper TTS on macOS, one per architecture:
# extraResources/piper/darwin/<arch>/python (arm64 and x64). Run before building the macOS app.
set -euo pipefail

if [ "$(uname -s)" != "Darwin" ]; then
  echo "fetch-piper-runtime: macOS only" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST_ROOT="$ROOT/extraResources/piper/darwin"
PYTHON_BUILD_TAG=20261021
PYTHON_VERSION=3.12.15
PIPER_TTS_VERSION=1.8.0
PYTHON_SHA256_ARM64=a18cc33862b53bd54a148c710def5375c1b47470cccedf817a19c2d211764584
PYTHON_SHA256_X64=869e0b30959beccc616ce14907439f4d0b3170c5830a2362dade07f07b0ed3b8

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fetch_arch() {
  local arch="$1" triple="$2" sha256="$3"
  local dest="$DEST_ROOT/$arch/python"
  local stamp="$dest/.runtime-version"
  local expected="python=$PYTHON_VERSION+$PYTHON_BUILD_TAG piper-tts=$PIPER_TTS_VERSION"

  if [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$expected" ]; then
    echo "[$arch] runtime up to date"
    return
  fi

  echo "[$arch] installing runtime ($expected)"
  rm -rf "$dest"
  local url="https://github.com/astral-sh/python-build-standalone/releases/download/$PYTHON_BUILD_TAG/cpython-${PYTHON_VERSION}%2B${PYTHON_BUILD_TAG}-${triple}-install_only.tar.gz"
  local archive="$TMP_DIR/$arch.tar.gz"
  curl -fsSL -o "$archive" "$url"
  echo "$sha256  $archive" | shasum -a 256 -c - >/dev/null
  mkdir -p "$DEST_ROOT/$arch"
  tar -xzf "$archive" -C "$DEST_ROOT/$arch"

  local python="$dest/bin/python3"
  if [ "$arch" = "x64" ]; then
    if ! arch -x86_64 /usr/bin/true 2>/dev/null; then
      echo "Rosetta 2 is required to install the x64 runtime: softwareupdate --install-rosetta --agree-to-license" >&2
      exit 1
    fi
    arch -x86_64 "$python" -m pip install --no-cache-dir --disable-pip-version-check --quiet "piper-tts==$PIPER_TTS_VERSION"
  else
    "$python" -m pip install --no-cache-dir --disable-pip-version-check --quiet "piper-tts==$PIPER_TTS_VERSION"
  fi

  find "$dest" -depth -name __pycache__ -type d -exec rm -rf {} +
  rm -rf "$dest/lib/python3.12/site-packages/pip" \
    "$dest"/lib/python3.12/site-packages/pip-*.dist-info \
    "$dest/lib/python3.12/ensurepip" \
    "$dest/lib/python3.12/idlelib" \
    "$dest/lib/python3.12/pydoc_data" \
    "$dest/lib/python3.12/test" \
    "$dest/bin/pip" "$dest/bin/pip3" "$dest/bin/pip3.12"
  find "$dest/lib/python3.12/site-packages" -type d \( -name tests -o -name test \) -prune -exec rm -rf {} +

  find "$dest" -type f -exec sh -c '
    file -b "$1" | grep -q "Mach-O" || exit 0
    codesign --force --sign - "$1" >/dev/null 2>&1 || { echo "codesign failed: $1" >&2; exit 1; }
  ' _ {} \;

  local machine
  if [ "$arch" = "x64" ]; then
    machine="$(arch -x86_64 "$python" -c 'import platform; print(platform.machine())')"
  else
    machine="$("$python" -c 'import platform; print(platform.machine())')"
  fi
  local expected_machine
  if [ "$arch" = "x64" ]; then expected_machine=x86_64; else expected_machine=arm64; fi
  if [ "$machine" != "$expected_machine" ]; then
    echo "[$arch] unexpected interpreter architecture: $machine" >&2
    exit 1
  fi

  echo "$expected" > "$stamp"
  echo "[$arch] runtime ready"
}

fetch_arch arm64 aarch64-apple-darwin "$PYTHON_SHA256_ARM64"
fetch_arch x64 x86_64-apple-darwin "$PYTHON_SHA256_X64"
