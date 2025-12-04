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
echo "[1/4] Building Docker image..."
docker build $NO_CACHE \
    -f "$PROJECT_ROOT/Dockerfile.linux.mos12" \
    -t cetus-linux-appimage:latest \
    "$PROJECT_ROOT"

# Step 2: Run container and create AppDir
echo "[2/4] Creating AppDir inside container..."
docker run --rm \
    -v "$PROJECT_ROOT":/build \
    -w /build/Cetus \
    cetus-linux-appimage:latest \
    bash -c "
        echo 'AppDir created. Contents:' && \
        find /build/Cetus/AppDir -type f | head -20
    "

# Step 3: Download appimagetool on host (avoid FUSE issues in Docker)
echo "[3/4] Setting up appimagetool on host..."
APPIMAGETOOL="$PROJECT_ROOT/appimagetool-x86_64.AppImage"
if [ ! -f "$APPIMAGETOOL" ]; then
    echo "Downloading appimagetool..."
    wget -q https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage \
        -O "$APPIMAGETOOL" && chmod +x "$APPIMAGETOOL" || \
        { echo "Failed to download appimagetool. Trying to use system appimagetool..."; APPIMAGETOOL=$(command -v appimagetool || true); }
fi

if [ -z "$APPIMAGETOOL" ] || [ ! -f "$APPIMAGETOOL" ]; then
    echo "⚠ Warning: appimagetool not available."
    echo "  You can create AppImage manually:"
    echo "  mkdir -p $PROJECT_ROOT/artifacts && mv $PROJECT_ROOT/AppDir $PROJECT_ROOT/artifacts/"
    echo "  Or install 'appimagetool' on your system."
    exit 1
fi

# Step 4: Create AppImage using appimagetool on host
echo "[4/4] Creating AppImage using appimagetool..."
mkdir -p "$PROJECT_ROOT/artifacts"
"$APPIMAGETOOL" "$PROJECT_ROOT/Cetus/AppDir" "$PROJECT_ROOT/artifacts/Cetus-x86_64.AppImage" && \
    chmod +x "$PROJECT_ROOT/artifacts/Cetus-x86_64.AppImage" || \
    { echo "Failed to create AppImage. Check appimagetool output above."; exit 1; }

echo ""
if [ -f "$PROJECT_ROOT/artifacts/Cetus-x86_64.AppImage" ]; then
    ls -lh "$PROJECT_ROOT/artifacts/Cetus-x86_64.AppImage"
    echo ""
    echo "✓ AppImage successfully created: $PROJECT_ROOT/artifacts/Cetus-x86_64.AppImage"
    echo ""
    echo "To test on МОС 12 Linux:"
    echo "  ./artifacts/Cetus-x86_64.AppImage"
    echo ""
    echo "To install system-wide (optional):"
    echo "  sudo cp ./artifacts/Cetus-x86_64.AppImage /usr/local/bin/Cetus"
    echo "  sudo chmod +x /usr/local/bin/Cetus"
else
    echo "⚠ Warning: AppImage not found at expected location."
fi

echo ""
echo "=== Done ==="
