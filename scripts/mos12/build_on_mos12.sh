#!/usr/bin/env bash
set -euo pipefail

# Build Cetus RPM on MOS 12 using the system toolchain (required for ABI/rpm compatibility).
# Expected inputs (copied from mac):
#   - Cetus-1.0.tar.gz
#   - cetus.spec

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

echo "Installing build deps (dnf)..."
# Package names vary between MOS builds; install the common Qt5 dev toolchain.
# If some packages are not found, install the nearest equivalents from your MOS repo.
dnf -y install rpm-build gcc-c++ make cmake git \
  qt5-qtbase-devel qt5-qtdeclarative-devel qt5-qttools-devel qt5-qtquickcontrols2-devel \
  libX11-devel libxcb-devel libxkbcommon-devel mesa-libGL-devel || true

TOPDIR="$HOME/RPM"
mkdir -p "$TOPDIR"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

cp -f "$TARBALL" "$TOPDIR/SOURCES/"
cp -f "$SPEC" "$TOPDIR/SPECS/"

echo "Building RPM via rpmbuild in $TOPDIR..."
rpmbuild --define "_topdir $TOPDIR" -ba "$TOPDIR/SPECS/$(basename "$SPEC")"

echo "Done. Built RPMs:"
find "$TOPDIR/RPMS" -type f -name "*.rpm" -maxdepth 2 -print

echo "Install example:"
echo "  sudo dnf install $TOPDIR/RPMS/*/Cetus-*.rpm"
