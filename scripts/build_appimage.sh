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
echo ""
echo "AppDir structure:"
find "$PROJECT_ROOT/Cetus/AppDir" -type f -o -type d | head -50
echo ""
echo "Checking for required files:"
[ -f "$PROJECT_ROOT/Cetus/AppDir/AppRun" ] && echo "✓ AppRun found" || echo "✗ AppRun missing"
[ -f "$PROJECT_ROOT/Cetus/AppDir/usr/bin/Cetus" ] && echo "✓ Binary found" || echo "✗ Binary missing"
[ -f "$PROJECT_ROOT/Cetus/AppDir/usr/share/applications/Cetus.desktop" ] && echo "✓ .desktop file found" || echo "✗ .desktop file missing"
[ -d "$PROJECT_ROOT/Cetus/AppDir/usr/lib" ] && echo "✓ lib dir found" || echo "✗ lib dir missing"

# Step 3: Install appimagetool if needed
echo "[3/4] Setting up appimagetool..."

# Try system appimagetool first
APPIMAGETOOL=$(command -v appimagetool || true)

if [ -z "$APPIMAGETOOL" ]; then
    echo "Installing appimagetool from package manager..."
    if command -v apt-get &> /dev/null; then
        sudo apt-get update -o APT::Get::AllowUnauthenticated=true -qq 2>/dev/null || true
        sudo apt-get install -y -o APT::Get::AllowUnauthenticated=true appimagetool 2>/dev/null || \
            { echo "⚠ Could not install via apt-get. Trying to download binary..."; }
    fi
    APPIMAGETOOL=$(command -v appimagetool || true)
fi

# If still not found, download AppImageKit binary
if [ -z "$APPIMAGETOOL" ]; then
    echo "Downloading appimagetool binary from GitHub..."
    APPIMAGETOOL_BIN="$PROJECT_ROOT/appimagetool-x86_64.AppImage"
    if [ ! -f "$APPIMAGETOOL_BIN" ]; then
        wget -q https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage \
            -O "$APPIMAGETOOL_BIN" 2>/dev/null && chmod +x "$APPIMAGETOOL_BIN" || \
            { echo "❌ Failed to download appimagetool"; exit 1; }
    fi
    APPIMAGETOOL="$APPIMAGETOOL_BIN"
fi

echo "Using appimagetool: $APPIMAGETOOL"

# Step 4: Create AppImage using appimagetool
echo "[4/4] Creating AppImage using appimagetool..."
mkdir -p "$PROJECT_ROOT/artifacts"

if [ ! -d "$PROJECT_ROOT/Cetus/AppDir" ]; then
    echo "❌ Error: AppDir not found at $PROJECT_ROOT/Cetus/AppDir"
    exit 1
fi

# Ensure a .desktop file exists at AppDir root (some appimagetool builds require it)
if ! ls "$PROJECT_ROOT/Cetus/AppDir"/*.desktop >/dev/null 2>&1; then
    if [ -f "$PROJECT_ROOT/Cetus/AppDir/usr/share/applications/Cetus.desktop" ]; then
        echo "Copying .desktop file to AppDir root..."
        cp "$PROJECT_ROOT/Cetus/AppDir/usr/share/applications/Cetus.desktop" "$PROJECT_ROOT/Cetus/AppDir/Cetus.desktop"
    else
        echo "❌ No .desktop file found in AppDir or usr/share/applications. Aborting."
        exit 1
    fi
fi

# If appimagetool is an AppImage, we need to extract it or install FUSE
if [[ "$APPIMAGETOOL" == *.AppImage ]]; then
    echo "Detected AppImage format. Attempting to extract and use binary..."
    
    # Try to extract appimagetool
    APPIMAGETOOL_DIR=$(mktemp -d)
    "$APPIMAGETOOL" --appimage-extract > /dev/null 2>&1 || true
    
    # Check if AppRun was extracted
    if [ -f "squashfs-root/AppRun" ]; then
        APPIMAGETOOL_BIN="$PWD/squashfs-root/AppRun"
        echo "Using extracted appimagetool: $APPIMAGETOOL_BIN"
        "$APPIMAGETOOL_BIN" "$PROJECT_ROOT/Cetus/AppDir" "$PROJECT_ROOT/artifacts/Cetus-x86_64.AppImage"
        rm -rf squashfs-root
    else
        # Fallback: try to install libfuse2 and run AppImage
        echo "Attempting to install libfuse2 for AppImage support..."
        sudo apt-get update -o APT::Get::AllowUnauthenticated=true -qq 2>/dev/null || true
        sudo apt-get install -y -o APT::Get::AllowUnauthenticated=true libfuse2 2>/dev/null || true
        
        # Try running appimagetool again
        if "$APPIMAGETOOL" "$PROJECT_ROOT/Cetus/AppDir" "$PROJECT_ROOT/artifacts/Cetus-x86_64.AppImage" 2>&1; then
            echo "✓ AppImage created with libfuse2"
        else
            echo "❌ Failed to create AppImage. Try manually:"
            echo "   appimagetool $PROJECT_ROOT/Cetus/AppDir $PROJECT_ROOT/artifacts/Cetus-x86_64.AppImage"
            exit 1
        fi
    fi
else
    # Regular appimagetool binary
    "$APPIMAGETOOL" "$PROJECT_ROOT/Cetus/AppDir" "$PROJECT_ROOT/artifacts/Cetus-x86_64.AppImage"
fi

if [ -f "$PROJECT_ROOT/artifacts/Cetus-x86_64.AppImage" ]; then
    chmod +x "$PROJECT_ROOT/artifacts/Cetus-x86_64.AppImage"
    echo ""
    ls -lh "$PROJECT_ROOT/artifacts/Cetus-x86_64.AppImage"
    echo ""
    echo "✓ AppImage successfully created: $PROJECT_ROOT/artifacts/Cetus-x86_64.AppImage"
    echo ""
    echo "To test on МОС 12 Linux:"
    echo "  ./artifacts/Cetus-x86_64.AppImage"
else
    echo "❌ Error: AppImage not created"
    exit 1
fi

echo ""
echo "=== Done ==="
