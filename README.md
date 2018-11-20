Cross compilation with MSVC on Linux
====================================

This is a reproducible Dockerfile for cross compiling with MSVC on Linux,
usable as base image for CI style setups.

This requires a zipped package of a real MSVC installation from Windows
(currently only supporting MSVC 2017, tested with 15.8 and 15.9), which
isn't redistributable.

To build the docker image, zip (Send to, Compressed (zipped) folder)
the following directories:

    C:\Program Files (x86)\Microsoft Visual Studio\2017\Community\VC
    C:\Program Files (x86)\Windows Kits\10

Host the zip files somewhere, then build the docker image like this:

    docker build --build-arg MSVC_URL=http://path/to/your/VC.zip --build-arg SDK_URL=http://path/to/your/10.zip .

After building the docker image, there are 4 directories with tools,
in `/opt/msvc2017/bin/<arch>`, for all architectures out of `x86`,
`x64`, `arm` and `arm64`, that should be added to the PATH before building
with it.
