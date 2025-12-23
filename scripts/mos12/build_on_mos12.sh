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
    if dnf -q list --available "$pkg" >/dev/null 2>&1; then
      packages_to_install+=("$pkg")
    fi
  done
  if ((${#packages_to_install[@]} > 0)); then
    dnf -y install "${packages_to_install[@]}"
  fi
}

dnf_install_first_found() {
  # Usage: dnf_install_first_found "label" pkgA pkgB ...
  local label=$1
  shift
  local pkg
  for pkg in "$@"; do
    if dnf -q list --available "$pkg" >/dev/null 2>&1; then
      echo "Installing $label: $pkg"
      dnf -y install "$pkg"
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
  provider=$(dnf -q provides "$file_path" 2>/dev/null | awk '/^[A-Za-z0-9_.+-]+\.[A-Za-z0-9_]+[[:space:]]/{print $1; exit}')

  if [[ -n "$provider" ]]; then
    echo "Installing $label provider: $provider"
    dnf -y install "$provider"
    return 0
  fi

  return 1
}

echo "Installing build deps (dnf)..."
dnf -y makecache || true

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
