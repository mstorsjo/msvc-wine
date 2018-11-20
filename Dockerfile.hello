ARG BASE=msvc-wine
FROM $BASE

COPY hello.c ./

RUN \
    wineserver -p && \
    wine wineboot && \
    for arch in x86 x64 arm arm64; do \
        /opt/msvc2017/bin/$arch/cl hello.c -Fehello-$arch.exe -DWINAPI_FAMILY=WINAPI_FAMILY_APP || exit 1; \
    done
