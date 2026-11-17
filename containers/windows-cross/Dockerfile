FROM debian:bookworm-slim AS build
RUN apt-get update \
    && apt-get install -y --no-install-recommends cmake ninja-build \
       g++-mingw-w64-x86-64-posix g++-mingw-w64-i686-posix \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
# Whitelist the build inputs; signing keys and local build output stay on the host.
COPY CMakeLists.txt replacer.ico ./
COPY cmake/ cmake/
COPY src/ src/
COPY tests/ tests/
ARG CONFIGURATION=Release
RUN cmake -S . -B /build/x64 -G Ninja \
      -DCMAKE_TOOLCHAIN_FILE=/src/cmake/mingw-w64.cmake \
      -DCMAKE_BUILD_TYPE=${CONFIGURATION} \
      -DCMAKE_RUNTIME_OUTPUT_DIRECTORY=/out/x64/${CONFIGURATION} \
      -DNOTEPADREPLACER_BUILD_CONTEXT_MENU=ON \
    && cmake --build /build/x64 --parallel 2 \
    && cmake -S . -B /build/x86 -G Ninja \
      -DCMAKE_TOOLCHAIN_FILE=/src/cmake/mingw-w64.cmake -DMINGW_ARCH=i686 \
      -DCMAKE_BUILD_TYPE=${CONFIGURATION} \
      -DCMAKE_RUNTIME_OUTPUT_DIRECTORY=/out/x86/${CONFIGURATION} \
      -DNOTEPADREPLACER_BUILD_CONTEXT_MENU=OFF \
    && cmake --build /build/x86 --parallel 2
FROM scratch AS artifacts
COPY --from=build /out/ /
