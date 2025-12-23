#!/usr/bin/env bash
set -euo pipefail

# Build Cetus RPM on MOS 12 using the MOS 12 toolchain.
# This avoids ABI / rpm-feature mismatches (glibc, rpmlib capabilities).

TARBALL=${1:-Cetus-1.0.tar.gz}
SPEC=${2:-cetus.spec}

if [[ ! -f "$TARBALL" ]]; then
  echo "ERROR: tarball not found: $TARBALL" >&2
  exit 1
fi
if [[ ! -f "$SPEC" ]]; then
  echo "ERROR: spec not found: $SPEC" >&2
  exit 1
fi

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
    dnf "${DNF_INSTALL_FLAGS[@]}" install "${packages_to_install[@]}"
  fi
}

dnf_install_first_found() {
  # Usage: dnf_install_first_found "label" pkgA pkgB ...
  local label=$1
  shift
  local pkg
  for pkg in "$@"; do
    if [[ "${ARCH:-}" == "x86_64" ]] && dnf -q list --available "${pkg}.x86_64" >/dev/null 2>&1; then
      echo "Installing $label: $pkg"
      dnf "${DNF_INSTALL_FLAGS[@]}" install "${pkg}.x86_64"
      return 0
    elif [[ "${ARCH:-}" == "x86_64" ]] && dnf -q list --available "${pkg}.noarch" >/dev/null 2>&1; then
      echo "Installing $label: $pkg"
      dnf "${DNF_INSTALL_FLAGS[@]}" install "${pkg}.noarch"
      return 0
    elif dnf -q list --available "$pkg" >/dev/null 2>&1; then
      echo "Installing $label: $pkg"
      dnf "${DNF_INSTALL_FLAGS[@]}" install "$pkg"
      return 0
    fi
  done
  echo "WARN: could not find a package for: $label" >&2
  return 1
}

dnf_install_provider_of_file() {
  # Usage: dnf_install_provider_of_file "/usr/bin/qmake" "label"
  # Attempts to install the first package that provides the given file.
  local file_path=$1
  local label=${2:-provider}

  # dnf provides output differs across distros; we extract the first "name.arch" line.
  local provider
  if [[ "${ARCH:-}" == "x86_64" ]]; then
    provider=$(dnf -q provides "$file_path" 2>/dev/null | awk '/^[A-Za-z0-9_.+-]+\.x86_64[[:space:]]/{print $1; exit}')
  fi
  if [[ -z "${provider:-}" ]]; then
    if [[ "${ARCH:-}" == "x86_64" ]]; then
      provider=$(dnf -q provides "$file_path" 2>/dev/null | awk '/^[A-Za-z0-9_.+-]+\.noarch[[:space:]]/{print $1; exit}')
    fi
  fi
  if [[ -z "${provider:-}" ]]; then
    provider=$(dnf -q provides "$file_path" 2>/dev/null | awk '/^[A-Za-z0-9_.+-]+\.[A-Za-z0-9_]+[[:space:]]/{print $1; exit}')
  fi

  if [[ -n "$provider" ]]; then
    echo "Installing $label provider: $provider"
    dnf "${DNF_INSTALL_FLAGS[@]}" install "$provider"
    return 0
  fi

  return 1
}

dnf_install_provider_of_capability() {
  # Usage: dnf_install_provider_of_capability "pkgconfig(Qt5Core)" "label"
  # Installs the first package that provides the given capability.
  local capability=$1
  local label=${2:-capability}

  local provider
  if [[ "${ARCH:-}" == "x86_64" ]]; then
    provider=$(dnf -q provides "$capability" 2>/dev/null | awk '/^[A-Za-z0-9_.+-]+\.x86_64[[:space:]]/{print $1; exit}')
  fi
  if [[ -z "${provider:-}" ]]; then
    if [[ "${ARCH:-}" == "x86_64" ]]; then
      provider=$(dnf -q provides "$capability" 2>/dev/null | awk '/^[A-Za-z0-9_.+-]+\.noarch[[:space:]]/{print $1; exit}')
    fi
  fi
  if [[ -z "${provider:-}" ]]; then
    provider=$(dnf -q provides "$capability" 2>/dev/null | awk '/^[A-Za-z0-9_.+-]+\.[A-Za-z0-9_]+[[:space:]]/{print $1; exit}')
  fi

  if [[ -n "$provider" ]]; then
    echo "Installing $label provider: $provider"
    dnf "${DNF_INSTALL_FLAGS[@]}" install "$provider"
    return 0
  fi

  return 1
}

echo "Installing build deps (dnf)..."
dnf -y makecache || true

ARCH=$(rpm --eval '%{_arch}' 2>/dev/null || uname -m)

# Common flags for all installs. On x86_64 we avoid pulling 32-bit (-i686) packages,
# because mixed *-devel multilib frequently conflicts on /usr/include/* headers.
DNF_INSTALL_FLAGS=(-y --allowerasing)
if [[ "$ARCH" == "x86_64" ]]; then
  DNF_INSTALL_FLAGS+=(--exclude='*.i686')
fi

# MOS 12 may have some 32-bit (-i686) *-devel packages installed.
# Those often conflict with 64-bit (-x86_64) *-devel packages on headers in /usr/include.
# Example seen in the wild: lib64ffi-devel conflicts with libffi-devel.i686 on /usr/include/ffi.h.
if [[ "$ARCH" == "x86_64" ]]; then
  if rpm -q libffi-devel.i686 >/dev/null 2>&1; then
    echo "Removing conflicting 32-bit package: libffi-devel.i686"
    dnf -y remove libffi-devel.i686 || true
  fi
fi

# rpmbuild must exist; fail hard if we can't install it.
if ! command -v rpmbuild >/dev/null 2>&1; then
  dnf_install_first_found "rpmbuild" rpm-build rpm-build-tools || true
fi
if ! command -v rpmbuild >/dev/null 2>&1; then
  echo "ERROR: rpmbuild not found. Install package 'rpm-build' (or enable the MOS 12 repos that provide it)." >&2
  exit 1
fi

# Toolchain (install what is available).
dnf_install_available gcc-c++ g++ gcc make cmake git

# pkg-config is commonly required for Qt module detection.
dnf_install_available pkgconf pkg-config

# Qt build deps: MOS 12 naming differs across repos/branches.
# Try both ALT-style and Fedora-style names; install whichever exist.
dnf_install_available \
  qt5-base-devel qt5-qtbase-devel \
  qt5-declarative-devel qt5-qtdeclarative-devel \
  qt5-tools-devel qt5-qttools-devel qttools5-dev-tools \
  qt5-quickcontrols2-devel qt5-qtquickcontrols2-devel qt5-qtquickcontrols2 \
  qt5-qmake qt5-qmake-devel

# X11 / OpenGL headers (install whatever exists)
dnf_install_available libx11-devel libxcb-devel libxkbcommon-devel \
  mesa-libGL-devel mesa-libgl-devel libGL-devel libglvnd-devel

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

# Pick qmake (prefer qmake-qt5) and print info.
QMAKE_BIN=$(command -v qmake-qt5 2>/dev/null || command -v qmake 2>/dev/null || true)
if [[ -z "$QMAKE_BIN" ]]; then
  echo "ERROR: internal: qmake detection failed." >&2
  exit 1
fi

echo "qmake selected: $QMAKE_BIN"
if "$QMAKE_BIN" -query QT_VERSION >/dev/null 2>&1; then
  echo "Qt version: $($QMAKE_BIN -query QT_VERSION)"
  echo "QT_INSTALL_PREFIX: $($QMAKE_BIN -query QT_INSTALL_PREFIX 2>/dev/null || true)"
  echo "QT_INSTALL_LIBS:   $($QMAKE_BIN -query QT_INSTALL_LIBS 2>/dev/null || true)"
else
  echo "WARN: '$QMAKE_BIN -query' failed; Qt installation may be incomplete." >&2
fi

# Ensure Qt5 module development packages exist. The error you got:
#   Unknown module(s) in QT: core gui qml quick widgets
# happens when the Qt5 .pri/module files are missing (typically devel packages).
# MOS 12 package names vary, so we resolve by provided capabilities.
dnf_install_provider_of_capability "pkgconfig(Qt5Core)" "Qt5Core" || true
dnf_install_provider_of_capability "pkgconfig(Qt5Gui)" "Qt5Gui" || true
dnf_install_provider_of_capability "pkgconfig(Qt5Widgets)" "Qt5Widgets" || true
dnf_install_provider_of_capability "pkgconfig(Qt5Qml)" "Qt5Qml" || true
dnf_install_provider_of_capability "pkgconfig(Qt5Quick)" "Qt5Quick" || true

# QuickControls2 is optional depending on QML imports, but try if available.
dnf_install_provider_of_capability "pkgconfig(Qt5QuickControls2)" "Qt5QuickControls2" || true

# Fallback: if Qt5Core pkg-config is still not found, try installing common Qt5 devel packages by name.
# This handles cases where capabilities are not advertised or repos have different naming.
if command -v pkg-config >/dev/null 2>&1 && ! pkg-config --exists Qt5Core 2>/dev/null; then
  echo "Qt5Core pkg-config not found after provider installs; trying fallback Qt5 devel packages..."
  dnf_install_available \
    qt5-base-devel qt5-qtbase-devel libqt5-base-devel qt5-devel qt-devel \
    qt5-declarative-devel qt5-qtdeclarative-devel libqt5-declarative-devel \
    qt5-tools-devel qt5-qttools-devel libqt5-tools-devel \
    qt5-quickcontrols2-devel qt5-qtquickcontrols2-devel libqt5-quickcontrols2-devel
fi

if ! command -v lupdate >/dev/null 2>&1; then
  echo "WARN: lupdate not found (OK for MOS 12 build: CETUS_NO_LINGUIST disables translation rebuild)." >&2
fi

if ! command -v lrelease >/dev/null 2>&1; then
  echo "WARN: lrelease not found (OK for MOS 12 build: CETUS_NO_LINGUIST disables translation rebuild)." >&2
fi

echo "Using rpmbuild: $(command -v rpmbuild)"
echo "Using qmake candidates:"
command -v qmake-qt5 >/dev/null 2>&1 && echo "  qmake-qt5: $(command -v qmake-qt5)" || true
command -v qmake >/dev/null 2>&1 && echo "  qmake:     $(command -v qmake)" || true
if command -v lupdate >/dev/null 2>&1 || command -v lrelease >/dev/null 2>&1; then
  echo "Using Qt translation tools:"
  command -v lupdate >/dev/null 2>&1 && echo "  lupdate:   $(command -v lupdate)" || true
  command -v lrelease >/dev/null 2>&1 && echo "  lrelease:  $(command -v lrelease)" || true
fi

TOPDIR="$HOME/RPM"
mkdir -p "$TOPDIR"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

cp -f "$TARBALL" "$TOPDIR/SOURCES/"
cp -f "$SPEC" "$TOPDIR/SPECS/"

echo "Building RPM via rpmbuild in $TOPDIR..."
set +e
rpmbuild --define "_topdir $TOPDIR" -ba "$TOPDIR/SPECS/$(basename "$SPEC")"
status=$?
set -e

if [[ $status -ne 0 ]]; then
  echo "ERROR: rpmbuild failed (exit $status)." >&2
  echo "Tip: if you see a policy error like 'disallows root', run this script under a regular user (not root)." >&2
  exit $status
fi

echo "Done. Built RPMs:"
find "$TOPDIR/RPMS" -maxdepth 3 -type f -name "*.rpm" -print

echo "Install example:"
echo "  sudo dnf install $TOPDIR/RPMS/*/Cetus-*.rpm"
