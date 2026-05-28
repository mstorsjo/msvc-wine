# syntax=docker/dockerfile:1
FROM ubuntu:26.04 AS base

RUN rm -f /etc/apt/apt.conf.d/docker-clean; echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt update && apt-get --no-install-recommends install -y \
    ca-certificates \
    gnupg \
    msitools \
    python3 \
    wget \
    wine

# Initialize the wine environment. Wait until the wineserver process has
# exited before closing the session, to avoid corrupting the wine prefix.
RUN $(command -v wine64 || command -v wine || false) wineboot --init && \
    while pgrep wineserver > /dev/null; do sleep 1; done

COPY --link lowercase fixinclude install.sh vsdownload.py msvctricks.cpp /opt/msvc/
COPY --link wrappers/* /opt/msvc/wrappers/
COPY --link msvcenv-native.sh /opt/msvc/

WORKDIR /opt/msvc

RUN --mount=type=cache,target=/var/cache/vsdownload,sharing=locked \
    PYTHONUNBUFFERED=1 ./vsdownload.py --accept-license \
      --cache=/var/cache/vsdownload --dest=/opt/msvc && \
    ./install.sh /opt/msvc

# Later stages which actually uses MSVC can ideally start a persistent
# wine server like this:
#RUN wineserver -p && \
#    $(command -v wine64 || command -v wine || false) wineboot && \
