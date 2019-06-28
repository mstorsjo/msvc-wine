FROM ubuntu:18.04

RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y unzip curl wine-development

WORKDIR /opt/msvc2017

ARG MSVC_URL
ARG SDK_URL

COPY lowercase fixinclude install.sh ./
COPY wrappers/* ./wrappers/
RUN curl -LO $MSVC_URL && \
    curl -LO $SDK_URL && \
    ./install.sh $(basename $MSVC_URL) $(basename $SDK_URL) /opt/msvc2017 && \
    rm $(basename $MSVC_URL) $(basename $SDK_URL) lowercase fixinclude install.sh && \
    rm -rf wrappers

# Initialize the wine environment. Wait until the wineserver process has
# exited before closing the session, to avoid corrupting the wine prefix.
RUN wine wineboot --init && \
    while pgrep wineserver > /dev/null; do sleep 1; done

# Later stages which actually uses MSVC can ideally start a persistent
# wine server like this:
#RUN wineserver -p && \
#    wine wineboot && \
