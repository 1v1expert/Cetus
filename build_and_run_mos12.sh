#!/bin/bash
set -e

dnf_install_available() {
  # Installs only packages that exist in enabled repos.
  # Usage: dnf_install_available pkg1 pkg2 ...
  local packages_to_install=()
  local pkg
  for pkg in "$@"; do
    if [[ "${ARCH:-}" == "x86_64" ]]; then
      # Only install variants that can exist alongside --exclude=*.i686.
      if dnf -q list --available "${pkg}.x86_64" >/dev/null 2>&1; then
        packages_to_install+=("${pkg}.x86_64")
      elif dnf -q list --available "${pkg}.noarch" >/dev/null 2>&1; then
        packages_to_install+=("${pkg}.noarch")
      else
        # Likely i686-only or not present; skip silently.
        :
      fi
    else
      if dnf -q list --available "$pkg" >/dev/null 2>&1; then
        packages_to_install+=("$pkg")
      fi
    fi
  done
  if ((${#packages_to_install[@]} > 0)); then
    dnf -y install "${packages_to_install[@]}"
  fi
}

echo "Updating system packages..."
dnf -y makecache

ARCH=$(rpm --eval '%{_arch}' 2>/dev/null || uname -m)

echo "Installing build dependencies..."
# Toolchain
dnf_install_available gcc-c++ g++ gcc make cmake git

# pkg-config
dnf_install_available pkgconf pkg-config

# Qt build deps: MOS 12 ALT Linux naming
# Install meta-package qt5-devel which should pull all needed dependencies
dnf_install_available qt5-devel qt5-tools qt5-linguist qt5-assistant qt5-designer

# Install individual Qt5 devel packages as fallback
dnf_install_available \
  libqt5core-devel libqt5gui-devel libqt5widgets-devel \
  libqt5qml-devel libqt5quick-devel \
  libqt5tools-devel \
  libqt5quickcontrols2-devel

# X11 / OpenGL headers
dnf_install_available libx11-devel libxcb-devel libxkbcommon-devel \
  mesa-libGL-devel mesa-libgl-devel libGL-devel libglvnd-devel

# Additional libs
dnf_install_available \
  libqt5core5 libqt5gui5 libqt5widgets5 libqt5qml5 libqt5quick5 \
  libqt5declarative5 libqt5tools5 \
  qt5-image-formats-plugins \
  libxkbcommon-x11-devel libgl1-mesa-devel libxkbfile-devel \
  libxcb1 libxcb-render-util0 libxcb-icccm4 libxcb-image0 \
  libxcb-keysyms1 libxcb-randr0 libxcb-shape0 libxcb-xfixes0 \
  libxcb-sync1 libxcb-xinerama0 libxrender1 libx11-xcb1 \
  libxkbcommon0 libxkbcommon-x11-0 libxss1 libsm6 libice6 \
  ca-certificates wget curl appstream desktop-file-utils \
  fuse libfuse-devel file patchelf python3 perl

# Ensure qmake exists (some MOS repos ship it under different package names).
if ! command -v qmake-qt5 >/dev/null 2>&1 && ! command -v qmake >/dev/null 2>&1; then
  echo "qmake not found after initial deps install; trying to discover provider..."

  # Common paths; try both.
  dnf_install_provider_of_file "*/qmake" "qmake" || true
  dnf_install_provider_of_file "/usr/bin/qmake" "qmake" || true
  dnf_install_provider_of_file "/usr/bin/qmake-qt5" "qmake-qt5" || true

  # Last resort: try a few very common names.
  dnf_install_available qt5-qmake qt5-qmake-devel qt-qmake qt-qmake-devel qtbase5-dev-tools || true
fi

if ! command -v qmake-qt5 >/dev/null 2>&1 && ! command -v qmake >/dev/null 2>&1; then
  echo "ERROR: qmake was not found and could not be installed from enabled repos." >&2
  echo "Please enable the MOS 12 repository that contains Qt development packages." >&2
  echo "Useful commands to diagnose on MOS 12:" >&2
  echo "  dnf repolist" >&2
  echo "  dnf search qmake" >&2
  echo "  dnf provides '*/qmake'" >&2
  exit 1
fi

# Pick qmake (prefer the one with working mkspecs)
QMAKE_CANDIDATES=()
command -v qmake-qt5 >/dev/null 2>&1 && QMAKE_CANDIDATES+=("qmake-qt5")
command -v qmake >/dev/null 2>&1 && QMAKE_CANDIDATES+=("qmake")
command -v qmake5 >/dev/null 2>&1 && QMAKE_CANDIDATES+=("qmake5")
[[ -x "/usr/lib/qt5/bin/qmake" ]] && QMAKE_CANDIDATES+=("/usr/lib/qt5/bin/qmake")
[[ -x "/usr/lib64/qt5/bin/qmake" ]] && QMAKE_CANDIDATES+=("/usr/lib64/qt5/bin/qmake")

QMAKE_BIN=""
for candidate in "${QMAKE_CANDIDATES[@]}"; do
  echo "Testing qmake candidate: $candidate"
  # Simplified check: just verify qmake can query Qt version
  if "$candidate" -query QT_VERSION >/dev/null 2>&1; then
    QT_VER=$("$candidate" -query QT_VERSION 2>/dev/null || echo "unknown")
    echo "Selected qmake: $candidate (Qt version: $QT_VER)"
    QMAKE_BIN="$candidate"
    break
  else
    echo "Rejected $candidate: cannot query Qt version"
  fi
done

if [[ -z "$QMAKE_BIN" ]]; then
  echo "No working qmake found; trying to install additional Qt5 packages..."
  dnf_install_available qt5-qtdeclarative qt5-qtbase-gui
  # Retry qmake selection with simplified check
  for candidate in "${QMAKE_CANDIDATES[@]}"; do
    echo "Retesting qmake candidate: $candidate"
    if "$candidate" -query QT_VERSION >/dev/null 2>&1; then
      QT_VER=$("$candidate" -query QT_VERSION 2>/dev/null || echo "unknown")
      echo "Selected qmake: $candidate (Qt version: $QT_VER)"
      QMAKE_BIN="$candidate"
      break
    else
      echo "Still rejected $candidate: cannot query Qt version"
    fi
  done
fi

if [[ -z "$QMAKE_BIN" ]]; then
  echo "ERROR: No working qmake found." >&2
  echo "Qt5 devel installation on MOS 12 may be incomplete." >&2
  echo "Trying to use qmake-qt5 directly as last resort..." >&2
  if command -v qmake-qt5 >/dev/null 2>&1; then
    QMAKE_BIN="qmake-qt5"
    echo "Using qmake-qt5 directly without validation" >&2
  elif command -v qmake >/dev/null 2>&1; then
    QMAKE_BIN="qmake"
    echo "Using qmake directly without validation" >&2
  else
    echo "ERROR: No qmake executable found at all." >&2
    echo "Please install Qt5 development packages manually: sudo dnf install qt5-devel" >&2
    exit 1
  fi
fi

echo "qmake selected: $QMAKE_BIN"

# Ensure Qt5 module development packages exist.
dnf_install_provider_of_capability "pkgconfig(Qt5Core)" "Qt5Core" || true
dnf_install_provider_of_capability "pkgconfig(Qt5Gui)" "Qt5Gui" || true
dnf_install_provider_of_capability "pkgconfig(Qt5Widgets)" "Qt5Widgets" || true
dnf_install_provider_of_capability "pkgconfig(Qt5Qml)" "Qt5Qml" || true
dnf_install_provider_of_capability "pkgconfig(Qt5Quick)" "Qt5Quick" || true

# QuickControls2 is optional depending on QML imports, but try if available.
dnf_install_provider_of_capability "pkgconfig(Qt5QuickControls2)" "Qt5QuickControls2" || true

# Fallback: if Qt5Core pkg-config is still not found, try installing common Qt5 devel packages by name.
if command -v pkg-config >/dev/null 2>&1 && ! pkg-config --exists Qt5Core 2>/dev/null; then
  echo "Qt5Core pkg-config not found after provider installs; trying fallback Qt5 devel packages..."
  dnf_install_available \
    libqt5core-devel libqt5gui-devel libqt5widgets-devel qt5-devel qt-devel \
    libqt5qml-devel libqt5quick-devel libqt5declarative-devel \
    libqt5tools-devel \
    libqt5quickcontrols2-devel libqt5qtquickcontrols2-devel
fi

echo "Creating build directory..."
mkdir -p build-linux
cd build-linux

echo "Building Cetus..."
"$QMAKE_BIN" ../Cetus.pro
make -j$(nproc)

echo "Running Cetus (in background)..."
./Cetus &
Cetus_PID=$!
echo "Cetus started with PID $Cetus_PID. Waiting 10 seconds for testing..."
sleep 10

# Optionally kill it after testing
kill $Cetus_PID 2>/dev/null || true

echo "Building AppImage..."

# Create AppDir structure
mkdir -p ../AppDir/usr/bin
mkdir -p ../AppDir/usr/lib
mkdir -p ../AppDir/usr/share/applications
mkdir -p ../AppDir/usr/share/icons/hicolor/scalable/apps

# Copy binary
cp Cetus ../AppDir/usr/bin/

# Download and extract linuxdeploy
cd /tmp
wget -q https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
chmod +x linuxdeploy-x86_64.AppImage
./linuxdeploy-x86_64.AppImage --appimage-extract
mv squashfs-root /linuxdeploy

# Copy Qt libraries and plugins manually (adapted for ALT Linux paths)
cd ..
mkdir -p AppDir/usr/lib
ldd build-linux/Cetus | awk '{print $3}' | grep '^/' | \
    grep -v 'libc\|libm\|libpthread\|libdl\|librt\|libselinux\|libresolv\|libgcc_s\|libstdc++' | \
    xargs -I {} cp {} AppDir/usr/lib/ 2>/dev/null || true

# Remove accidentally bundled base/system libs
rm -f AppDir/usr/lib/libselinux.so.* || true

# Copy additional X11/xcb deps (using ALT Linux lib64 paths)
cp /usr/lib64/libxcb*.so* AppDir/usr/lib/ 2>/dev/null || true
cp /usr/lib64/libxkbcommon*.so* AppDir/usr/lib/ 2>/dev/null || true
cp /usr/lib64/libX11-xcb.so* AppDir/usr/lib/ 2>/dev/null || true
cp /usr/lib64/libXrender.so* AppDir/usr/lib/ 2>/dev/null || true
cp /usr/lib64/libXss.so* AppDir/usr/lib/ 2>/dev/null || true
cp /usr/lib64/libSM.so* AppDir/usr/lib/ 2>/dev/null || true
cp /usr/lib64/libICE.so* AppDir/usr/lib/ 2>/dev/null || true

# Copy Qt plugins and QML (ALT Linux paths)
mkdir -p AppDir/usr/lib/qt5
cp -r /usr/lib64/qt5/plugins AppDir/usr/lib/qt5/ 2>/dev/null || true
cp -r /usr/lib64/qt5/qml AppDir/usr/lib/qt5/ 2>/dev/null || true

# Create Desktop Entry and Icon
printf '[Desktop Entry]\nType=Application\nName=Cetus\nComment=CNC Machine Control Application\nExec=Cetus\nIcon=Cetus\nCategories=Utility;\nTerminal=false\n' > AppDir/usr/share/applications/Cetus.desktop
printf '<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256"><rect width="256" height="256" fill="#4a90e2"/><text x="128" y="140" font-size="120" text-anchor="middle" fill="white">C</text></svg>' > AppDir/usr/share/icons/hicolor/scalable/apps/Cetus.svg

# Create AppRun script
cat > AppDir/AppRun << 'APPRUN_EOF'
#!/bin/bash
export APPDIR="$(cd "$(dirname "$0")" && pwd)"
export LD_LIBRARY_PATH="$APPDIR/usr/lib:$LD_LIBRARY_PATH"
export QT_PLUGIN_PATH="$APPDIR/usr/lib/qt5/plugins"
export QT_QPA_PLATFORM_PLUGIN_PATH="$APPDIR/usr/lib/qt5/plugins/platforms"
export QML2_IMPORT_PATH="$APPDIR/usr/lib/qt5/qml"
exec "$APPDIR/usr/bin/Cetus" "$@"
APPRUN_EOF
chmod +x AppDir/AppRun

# Download appimagetool and create AppImage
cd /tmp
wget -q https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage
chmod +x appimagetool-x86_64.AppImage
mkdir -p ../artifacts
./appimagetool-x86_64.AppImage ../AppDir ../artifacts/Cetus-x86_64.AppImage

echo "AppImage created at artifacts/Cetus-x86_64.AppImage"