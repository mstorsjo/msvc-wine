FROM ubuntu:18.04

RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y unzip curl wine-development

WORKDIR /opt/msvc2017

ARG MSVC_URL
ARG SDK_URL

COPY lowercase fixinclude ./
RUN curl -LO $MSVC_URL && \
    curl -LO $SDK_URL && \
    unzip $(basename $MSVC_URL) && \
    mv VC vc && \
    mv vc/Tools vc/tools && \
    mv vc/tools/MSVC vc/tools/msvc && \
    mkdir kits && \
    cd kits && \
    unzip ../$(basename $SDK_URL) && \
    cd 10 && \
    mv Lib lib && \
    mv Include include && \
    cd ../.. && \
    rm $(basename $MSVC_URL) $(basename $SDK_URL) && \
    if [ -d kits/10/Redist/10.*/ucrt/DLLs ]; then \
        REDIST=$(echo kits/10/Redist/10.*/ucrt/DLLs); \
    else \
        REDIST=kits/10/Redist/ucrt/DLLs; \
    fi && \
    for arch in x86 x64 arm arm64; do \
        cp $REDIST/x86/* vc/tools/msvc/*/bin/Hostx86/$arch || exit 1; \
        cp $REDIST/x64/* vc/tools/msvc/*/bin/Hostx64/$arch || exit 1; \
    done && \
    SDKVER=$(basename $(echo kits/10/include/* | awk '{print $NF}')) && \
    ./lowercase kits/10/include/$SDKVER/um && \
    ./lowercase kits/10/include/$SDKVER/shared && \
    ./fixinclude kits/10/include/$SDKVER/um && \
    ./fixinclude kits/10/include/$SDKVER/shared && \
    for arch in x86 x64 arm arm64; do \
        ./lowercase kits/10/lib/$SDKVER/um/$arch || exit 1; \
    done && \
    rm lowercase fixinclude

COPY wrappers/* ./wrappers/
RUN SDKVER=$(basename $(echo kits/10/include/* | awk '{print $NF}')) && \
    MSVCVER=$(basename $(echo vc/tools/msvc/* | awk '{print $NF}')) && \
    cat wrappers/msvcenv.sh | sed 's/MSVCVER=.*/MSVCVER='$MSVCVER/ | sed 's/SDKVER=.*/SDKVER='$SDKVER/ > tmp && \
    mv tmp wrappers/msvcenv.sh && \
    for arch in x86 x64 arm arm64; do \
        mkdir -p bin/$arch && \
        cp wrappers/* bin/$arch && \
        cat wrappers/msvcenv.sh | sed 's/ARCH=.*/ARCH='$arch/ > bin/$arch/msvcenv.sh || exit 1; \
    done && \
    rm -rf wrappers

# Initialize the wine environment. Wait until the wineserver process has
# exited before closing the session, to avoid corrupting the wine prefix.
RUN wine wineboot --init && \
    while pgrep wineserver > /dev/null; do sleep 1; done

# Later stages which actually uses MSVC can ideally start a persistent
# wine server like this:
#RUN wineserver -p && \
#    wine wineboot && \
