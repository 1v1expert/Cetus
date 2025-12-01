# Building Cetus (Windows) using Docker + MXE

This document shows how to build a Windows (MinGW) binary of Cetus using a Docker image based on MXE.

Notes:
- Building Qt with MXE (qt5) is heavy and may take many minutes to hours depending on machine and network.
- The produced binary will be a MinGW-built Windows executable (.exe) and accompanying DLLs.
- For native Windows containers (Windows images) Docker must run in Windows container mode — this setup uses MXE to cross-compile from Linux container.

Usage (recommended: use a bind-mount of the source rather than building the image each time):

1) Build the image locally (this will trigger building qt5 in MXE inside image):

```bash
docker build -t cetus-windows -f Dockerfile.windows .
```

2) Run the container (recommended: bind-mount workspace to speed up iteration):

```bash
# Using the image with bind mount (faster iteration)
docker run --rm -v "$PWD":/build/Cetus -v "$PWD"/artifacts:/build/artifacts cetus-windows
```

3) After successful build, check `artifacts/` for `.exe` and required `.dll` files.

If you prefer not to build Qt inside the image, you can use an MXE image that already contains the built Qt packages, or prepare a CI cache.

Troubleshooting:
- If `/usr/lib/mxe/usr/bin/x86_64-w64-mingw32.static-qmake-qt5` is not present, ensure the MXE `qt5` package built successfully inside the image.
- You may need additional MXE packages depending on project dependencies; add them to the `make -C /usr/lib/mxe MXE_TARGETS=...` line in `Dockerfile.windows`.
