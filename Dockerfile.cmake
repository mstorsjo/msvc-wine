ARG BASE=msvc-wine
FROM $BASE

RUN apt-get update && \
    apt-get install -y --no-install-recommends git build-essential ninja-build

WORKDIR /build
RUN git clone https://gitlab.kitware.com/mstorsjo/cmake.git && \
    cd cmake && \
    git checkout 844ccd2280d11ada286d0e2547c0fa5ff22bd4db && \
    mkdir build && \
    cd build && \
    ../configure --prefix=/opt/cmake --parallel=$(nproc) -- -DCMAKE_USE_OPENSSL=OFF && \
    make -j$(nproc) && \
    make install

ENV PATH=/opt/cmake/bin:$PATH

RUN git clone https://github.com/mstorsjo/fdk-aac && \
    cd fdk-aac && \
    git checkout 7f328b93ee2aa8bb4e94613b6ed218e7525d8dc0

RUN wineserver -p && \
    wine64 wineboot && \
    cd fdk-aac && \
    mkdir build-msvc-arm64 && \
    cd build-msvc-arm64 && \
    export PATH=/opt/msvc/bin/arm64:$PATH && \
    CC=cl CXX=cl cmake .. -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_PROGRAMS=ON -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_CROSSCOMPILING=ON && \
    ninja
