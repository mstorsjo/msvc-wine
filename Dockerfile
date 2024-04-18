FROM ubuntu:22.04

RUN apt-get update && \
    apt-get install -y wine64 python3 msitools ca-certificates && \
    apt-get clean -y && \
    rm -rf /var/lib/apt/lists/*

# Initialize the wine environment. Wait until the wineserver process has
# exited before closing the session, to avoid corrupting the wine prefix.
RUN $(command -v wine64 || command -v wine || false) wineboot --init && \
    while pgrep wineserver > /dev/null; do sleep 1; done

WORKDIR /opt/msvc

COPY lowercase fixinclude install.sh vsdownload.py msvctricks.cpp ./
COPY wrappers/* ./wrappers/

RUN PYTHONUNBUFFERED=1 ./vsdownload.py --accept-license --dest /opt/msvc && \
    ./install.sh /opt/msvc && \
    rm lowercase fixinclude install.sh vsdownload.py && \
    rm -rf wrappers

COPY msvcenv-native.sh /opt/msvc

# Later stages which actually uses MSVC can ideally start a persistent
# wine server like this:
#RUN wineserver -p && \
#    $(command -v wine64 || command -v wine || false) wineboot && \
