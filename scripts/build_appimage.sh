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
CONTAINER_ID=$(docker run --rm -d \
    -v "$PROJECT_ROOT":/build \
    -w /build/Cetus \
    cetus-linux-appimage:latest \
    bash -c "echo 'AppDir ready'; sleep infinity")

# Wait for container to be ready
sleep 2

# Copy AppDir from container to host
echo "Copying AppDir from container..."
docker cp "$CONTAINER_ID":/build/Cetus/AppDir "$PROJECT_ROOT/AppDir"

# Stop container
docker stop "$CONTAINER_ID" 2>/dev/null || true

echo "AppDir copied to $PROJECT_ROOT/AppDir"
ls -la "$PROJECT_ROOT/AppDir/usr/bin/"

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

if [ ! -d "$PROJECT_ROOT/AppDir" ]; then
    echo "❌ Error: AppDir not found at $PROJECT_ROOT/AppDir"
    exit 1
fi

"$APPIMAGETOOL" "$PROJECT_ROOT/AppDir" "$PROJECT_ROOT/artifacts/Cetus-x86_64.AppImage"
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
