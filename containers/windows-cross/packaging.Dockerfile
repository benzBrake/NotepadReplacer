FROM debian:trixie-slim AS native-tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential clang cmake git ca-certificates libssl-dev \
    libxerces-c-dev uuid-dev zlib1g-dev pkg-config \
    && rm -rf /var/lib/apt/lists/*
# Pin the upstream revisions used in the packaging proof of concept.
RUN git init /opt/msix && git -C /opt/msix fetch --depth 1 \
    https://github.com/microsoft/msix-packaging.git 25a65f5c1690930813bcc10cdf1d59fa865f2bb1 \
    && git -C /opt/msix checkout --detach FETCH_HEAD
# The bundled Xerces and MSIX targets need C++17 with Debian 13's ICU.
RUN sed -i 's/set(CMAKE_CXX_STANDARD 14)/set(CMAKE_CXX_STANDARD 17)/' \
      /opt/msix/lib/xerces/CMakeLists.txt /opt/msix/CMakeLists.txt \
    && cmake -S /opt/msix -B /opt/msix/build -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_TOOLCHAIN_FILE=/opt/msix/cmake/linux.cmake -DLINUX=on \
      -DMSIX_PACK=on -DUSE_VALIDATION_PARSER=on -DMSIX_SAMPLES=off \
      -DMSIX_TESTS=off -Dtranscoder=iconv \
    && cmake --build /opt/msix/build --parallel 4
RUN git init /opt/osslsigncode && git -C /opt/osslsigncode fetch --depth 1 \
    https://github.com/mtrojnar/osslsigncode.git 868d6e95c603a8057e89336f12fe12b5d2258e00 \
    && git -C /opt/osslsigncode checkout --detach FETCH_HEAD \
    && cmake -S /opt/osslsigncode -B /opt/osslsigncode/build -DCMAKE_BUILD_TYPE=Release \
    && cmake --build /opt/osslsigncode/build --parallel 4

FROM debian:trixie-slim
RUN dpkg --add-architecture i386 && apt-get update \
    && apt-get install -y --no-install-recommends \
      wine wine32:i386 wine64 xvfb xauth curl ca-certificates openssl libicu76 \
    && rm -rf /var/lib/apt/lists/*
COPY --from=native-tools /opt/msix/build/bin/makemsix /usr/local/bin/makemsix
COPY --from=native-tools /opt/msix/build/lib/libmsix.so /usr/local/lib/libmsix.so
COPY --from=native-tools /opt/osslsigncode/build/osslsigncode /usr/local/bin/osslsigncode
RUN ldconfig
ENV WINEDEBUG=-all WINEPREFIX=/opt/wine
RUN curl -fL https://github.com/jrsoftware/issrc/releases/download/is-6_7_3/innosetup-6.7.3.exe \
      -o /tmp/innosetup.exe \
    && echo '9c73c3bae7ed48d44112a0f48e66742c00090bdb5bef71d9d3c056c66e97b732  /tmp/innosetup.exe' | sha256sum -c - \
    && xvfb-run -a wine /tmp/innosetup.exe /VERYSILENT /SUPPRESSMSGBOXES \
      /NORESTART /SP- '/DIR=C:\InnoSetup' \
    && wineserver -w && rm /tmp/innosetup.exe
COPY containers/windows-cross/package.sh /opt/notepadreplacer/package.sh
# Windows checkouts can use CRLF. Normalize the Linux entry point in the image.
RUN sed -i 's/\r$//' /opt/notepadreplacer/package.sh
ENTRYPOINT ["sh", "/opt/notepadreplacer/package.sh"]
