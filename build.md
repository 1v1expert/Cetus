docker build -f [Dockerfile.linux.mos12](http://_vscodecontentref_/0) -t cetus-static .
После сборки извлечь AppImage: docker run --rm -v $(pwd)/artifacts:/host cetus-static cp /build/artifacts/Cetus-x86_64.AppImage /host/
Протестировать AppImage на Ubuntu 18.04 и MOS 12.
