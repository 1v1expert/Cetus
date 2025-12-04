#!/bin/bash
# Build Cetus AppImage for МОС 12 (ALT Linux)
# Usage: ./scripts/build_appimage.sh [--no-cache]

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
NO_CACHE="${1:---no-cache}"

echo "=== Building Cetus AppImage for МОС 12 ==="
echo "Project root: $PROJECT_ROOT"
echo ""

# Step 1: Build Docker image
echo "[1/3] Building Docker image..."
docker build $NO_CACHE \
    -f "$PROJECT_ROOT/Dockerfile.linux.mos12" \
    -t cetus-mos12-appimage:latest \
    "$PROJECT_ROOT"

# Step 2: Run container and create AppDir
echo "[2/3] Creating AppDir inside container..."
docker run --rm \
    -v "$PROJECT_ROOT":/build \
    -w /build/Cetus \
    cetus-mos12-appimage:latest \
    bash -c "
        # AppDir is already created, now we'll use appimagetool to package
        appimagetool /build/Cetus/AppDir /build/artifacts/Cetus-x86_64.AppImage || \
        echo 'appimagetool not available in container, trying linuxdeployqt...' && \
        linuxdeployqt /build/Cetus/AppDir/usr/bin/Cetus -appimage -no-strip || \
        echo 'Warning: AppImage creation tools not fully available'
    "

# Step 3: Package AppImage on host (fallback/verification)
echo "[3/3] Verifying AppImage..."
if [ -f "$PROJECT_ROOT/artifacts/Cetus-x86_64.AppImage" ]; then
    chmod +x "$PROJECT_ROOT/artifacts/Cetus-x86_64.AppImage"
    ls -lh "$PROJECT_ROOT/artifacts/Cetus-x86_64.AppImage"
    echo ""
    echo "✓ AppImage successfully created: $PROJECT_ROOT/artifacts/Cetus-x86_64.AppImage"
    echo ""
    echo "To test on МОС 12 Linux:"
    echo "  ./Cetus-x86_64.AppImage"
    echo ""
    echo "To install system-wide (optional):"
    echo "  sudo mv Cetus-x86_64.AppImage /usr/local/bin/Cetus"
    echo "  sudo chmod +x /usr/local/bin/Cetus"
else
    echo "⚠ Warning: AppImage not found at expected location."
    echo "  Check Docker output above for build errors."
    echo "  Manual fallback: use AppDir directly or install dependencies and run qmake/make locally."
fi

echo ""
echo "=== Done ==="
