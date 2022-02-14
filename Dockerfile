FROM ubuntu:20.04

RUN apt-get update && \
    apt-get install -y wine64-development python msitools python-simplejson \
                       python-six ca-certificates && \
    apt-get clean -y && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /opt/msvc

COPY install.py vsdownload.py ./
COPY wrappers/* ./wrappers/

RUN PYTHONUNBUFFERED=1 ./vsdownload.py --accept-license --dest /opt/msvc && \
    ./install.py /opt/msvc && \
    rm install.py vsdownload.py && \
    rm -rf wrappers

# Initialize the wine environment. Wait until the wineserver process has
# exited before closing the session, to avoid corrupting the wine prefix.
RUN wine64 wineboot --init && \
    while pgrep wineserver > /dev/null; do sleep 1; done

# Later stages which actually uses MSVC can ideally start a persistent
# wine server like this:
#RUN wineserver -p && \
#    wine64 wineboot && \
