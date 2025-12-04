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

# Step 2: Create AppDir inside container
echo "[2/4] Creating AppDir inside container..."
rm -rf "$PROJECT_ROOT/Cetus/AppDir"

# Create a temporary container from the image (don't run, just create)
# Then copy AppDir from it
TEMP_CONTAINER=$(docker create cetus-linux-appimage:latest)

# Copy AppDir from the built image
echo "Copying AppDir from container image..."
docker cp "$TEMP_CONTAINER":/build/Cetus/AppDir "$PROJECT_ROOT/Cetus/AppDir"

# Remove temporary container
docker rm "$TEMP_CONTAINER" > /dev/null

# Verify AppDir was copied
if [ ! -d "$PROJECT_ROOT/Cetus/AppDir" ]; then
    echo "❌ Error: AppDir not copied from container"
    exit 1
fi

echo "✓ AppDir created successfully"
ls -la "$PROJECT_ROOT/Cetus/AppDir/usr/bin/"

# Step 3: Install appimagetool if needed
echo "[3/4] Setting up appimagetool..."

# Try system appimagetool first
APPIMAGETOOL=$(command -v appimagetool || true)

if [ -z "$APPIMAGETOOL" ]; then
    echo "Installing appimagetool from package manager..."
    if command -v apt-get &> /dev/null; then
        sudo apt-get update -qq && sudo apt-get install -y appimagetool || \
            { echo "Failed to install appimagetool via apt-get"; exit 1; }
    else
        echo "Error: apt-get not found. Install appimagetool manually."
        exit 1
    fi
    APPIMAGETOOL=$(command -v appimagetool)
fi

echo "Using appimagetool: $APPIMAGETOOL"

# Step 4: Create AppImage using appimagetool
echo "[4/4] Creating AppImage using appimagetool..."
mkdir -p "$PROJECT_ROOT/artifacts"

if [ ! -d "$PROJECT_ROOT/Cetus/AppDir" ]; then
    echo "❌ Error: AppDir not found at $PROJECT_ROOT/Cetus/AppDir"
    exit 1
fi

"$APPIMAGETOOL" "$PROJECT_ROOT/Cetus/AppDir" "$PROJECT_ROOT/artifacts/Cetus-x86_64.AppImage"
chmod +x "$PROJECT_ROOT/artifacts/Cetus-x86_64.AppImage"

echo ""
ls -lh "$PROJECT_ROOT/artifacts/Cetus-x86_64.AppImage"
echo ""
echo "✓ AppImage successfully created: $PROJECT_ROOT/artifacts/Cetus-x86_64.AppImage"
echo ""
echo "To test on МОС 12 Linux:"
echo "  ./artifacts/Cetus-x86_64.AppImage"

echo ""
echo "=== Done ==="
