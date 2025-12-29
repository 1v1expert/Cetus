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

echo "Creating build directory..."
mkdir -p build-linux
cd build-linux

echo "Building Cetus..."
qmake ../Cetus.pro
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