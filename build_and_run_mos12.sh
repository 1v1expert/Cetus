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

# Qt build deps
dnf_install_available \
  qt5-base-devel qt5-qtbase-devel \
  qt5-declarative-devel qt5-qtdeclarative-devel \
  qt5-tools-devel qt5-qttools-devel qttools5-dev-tools \
  qt5-quickcontrols2-devel qt5-qtquickcontrols2-devel qt5-qtquickcontrols2 \
  qt5-qmake qt5-qmake-devel

# X11 / OpenGL headers
dnf_install_available libx11-devel libxcb-devel libxkbcommon-devel \
  mesa-libGL-devel mesa-libgl-devel libGL-devel libglvnd-devel

# Additional libs
dnf_install_available \
  libqt5core5 libqt5gui5 libqt5widgets5 libqt5qml5 libqt5quick5 \
  libqt5network5 libqt5dbus5 libqt5sql5 qt5-image-formats-plugins \
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
  MKSPECS_DIR=$("$candidate" -query QT_INSTALL_MKSPECS 2>/dev/null || echo "")
  if [[ -n "$MKSPECS_DIR" && -d "$MKSPECS_DIR/modules" && -f "$MKSPECS_DIR/modules/qt_lib_core.pri" ]]; then
    echo "Selected qmake: $candidate (mkspecs found at $MKSPECS_DIR)"
    QMAKE_BIN="$candidate"
    break
  else
    echo "Rejected $candidate: mkspecs missing or incomplete"
  fi
done

if [[ -z "$QMAKE_BIN" ]]; then
  echo "No working qmake found; trying to install qt5-mkspecs and qt5-base..."
  dnf_install_available qt5-mkspecs qt5-qtbase-mkspecs qt5-base-mkspecs libqt5-mkspecs \
    qt5-base qt5-qtbase libqt5-base
  # Retry qmake selection
  for candidate in "${QMAKE_CANDIDATES[@]}"; do
    echo "Retesting qmake candidate: $candidate"
    MKSPECS_DIR=$("$candidate" -query QT_INSTALL_MKSPECS 2>/dev/null || echo "")
    if [[ -n "$MKSPECS_DIR" && -d "$MKSPECS_DIR/modules" && -f "$MKSPECS_DIR/modules/qt_lib_core.pri" ]]; then
      echo "Selected qmake: $candidate (mkspecs found at $MKSPECS_DIR)"
      QMAKE_BIN="$candidate"
      break
    else
      echo "Still rejected $candidate: mkspecs missing or incomplete"
    fi
  done
fi

if [[ -z "$QMAKE_BIN" ]]; then
  echo "ERROR: No working qmake found even after installing mkspecs." >&2
  echo "Qt5 devel installation on MOS 12 may be incomplete." >&2
  echo "Check dnf search qt5 | grep mkspecs" >&2
  exit 1
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
    qt5-base-devel qt5-qtbase-devel libqt5-base-devel qt5-devel qt-devel \
    qt5-declarative-devel qt5-qtdeclarative-devel libqt5-declarative-devel \
    qt5-tools-devel qt5-qttools-devel libqt5-tools-devel \
    qt5-quickcontrols2-devel qt5-qtquickcontrols2-devel libqt5-quickcontrols2-devel
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