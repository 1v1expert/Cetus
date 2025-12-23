#!/bin/bash
# Build script for Cetus on MOS 12

set -e

echo "Building Cetus RPM for MOS 12..."

# Create artifacts directory
mkdir -p artifacts

# Build the Docker image and create RPM
docker build -f Dockerfile.mos12 -t cetus-mos12 .

# Extract the RPM from the container
docker run --rm -v $(pwd)/artifacts:/host-artifacts cetus-mos12 cp /artifacts/Cetus-*.rpm /host-artifacts/

echo "RPM package created in artifacts/ directory"
echo "To install on MOS 12: dnf install ./Cetus-*.rpm"