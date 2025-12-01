#!/usr/bin/env bash
set -euo pipefail

# This script runs inside the MXE-based Docker image and builds Cetus
# Outputs are written to /build/artifacts

export MXE_TARGETS=x86_64-w64-mingw32.static

BUILD_DIR=/build/Cetus/build-windows
ARTIFACTS_DIR=/build/artifacts
mkdir -p "$BUILD_DIR"
mkdir -p "$ARTIFACTS_DIR"

echo "Using MXE toolchain from /usr/lib/mxe/usr/bin"
QMAKE=/usr/lib/mxe/usr/bin/x86_64-w64-mingw32.static-qmake-qt5

if [ ! -x "$QMAKE" ]; then
    echo "qmake for MXE not found: $QMAKE"
    echo "Available files in /usr/lib/mxe/usr/bin (first 50):"
    ls -1 /usr/lib/mxe/usr/bin | head -n 50
    exit 1
fi

cd "$BUILD_DIR"

echo "Running qmake..."
"$QMAKE" ../Cetus.pro -spec win32-g++

echo "Running make... this may take a while"
make -j"$(nproc)"

echo "Collecting artifacts..."
find . -maxdepth 2 -type f -name "*.exe" -o -name "*.dll" -o -name "*.pdb" | while read -r f; do
    cp --parents "$f" "$ARTIFACTS_DIR" || true
done

echo "Artifacts placed in: $ARTIFACTS_DIR"
ls -la "$ARTIFACTS_DIR"
