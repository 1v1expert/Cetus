#!/usr/bin/env bash
# Prepare a MOS 12-buildable source bundle (tarball + spec).
#
# Why this exists:
# RPMs built in ALT Sisyphus (or other newer distros) often REQUIRE newer glibc/rpm
# than MOS 12 provides (e.g. GLIBC_2.34, rpmlib(SetVersions), rpmlib(PayloadIsLzma)).
# The reliable solution is: build the binary RPM on MOS 12 itself.

set -euo pipefail

VERSION=1.0
NAME=Cetus
OUT_DIR="artifacts/mos12-src"

echo "Preparing source bundle for MOS 12 build..."
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

# Create a clean source tarball with a top-level folder NAME-VERSION/
STAGING_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGING_DIR"' EXIT

mkdir -p "$STAGING_DIR/${NAME}-${VERSION}"

# Prefer rsync for reliable excludes; fall back to tar if not available.
if command -v rsync >/dev/null 2>&1; then
	rsync -a \
		--exclude ".git" \
		--exclude "artifacts" \
		--exclude "build-*" \
		./ "$STAGING_DIR/${NAME}-${VERSION}/"
else
	tar --exclude='./.git' --exclude='./artifacts' --exclude='./build-*' \
		-cf - . | tar -xf - -C "$STAGING_DIR/${NAME}-${VERSION}/"
fi

tar -C "$STAGING_DIR" -czf "$OUT_DIR/${NAME}-${VERSION}.tar.gz" "${NAME}-${VERSION}"

cp -f "packaging/mos12/cetus.spec" "$OUT_DIR/cetus.spec"
cp -f "scripts/mos12/build_on_mos12.sh" "$OUT_DIR/build_on_mos12.sh"
chmod +x "$OUT_DIR/build_on_mos12.sh"

echo "Created: $OUT_DIR/${NAME}-${VERSION}.tar.gz"
echo "Created: $OUT_DIR/cetus.spec"
echo "Created: $OUT_DIR/build_on_mos12.sh"
echo
echo "Next (on MOS 12 machine):"
echo "  cd <folder_with_bundle>"
echo "  ./build_on_mos12.sh ${NAME}-${VERSION}.tar.gz cetus.spec"