Cross compilation with MSVC on Linux
====================================

This is a reproducible Dockerfile for cross compiling with MSVC on Linux,
usable as base image for CI style setups.

This downloads and unpacks the necessary Visual Studio components using
the same installer manifests as Visual Studio 2017/2019's installer
uses. Downloading and installing it requires accepting the license,
available at https://go.microsoft.com/fwlink/?LinkId=2086102 for the
currently latest version.

As Visual Studio isn't redistributable, the resulting docker image isn't
either.

Build the docker image like this:

    docker build .

After building the docker image, there are 4 directories with tools,
in `/opt/msvc/bin/<arch>`, for all architectures out of `x86`,
`x64`, `arm` and `arm64`, that should be added to the PATH before building
with it.

The installer scripts also work fine without docker; just run the following two commands:

    ./vsdownload.py --dest <dir>
    ./install.sh <dir>

The unpacking requires recent versions of msitools (0.98) and libgcab
(1.2); sufficiently new versions are available in e.g. Ubuntu 19.04.


# Build instructions for local installation

The following instructions are for setting up MSVC without docker.

## Prerequisites

```bash
apt-get update
apt-get install -y wine64-development python msitools python-simplejson python-six ca-certificates winbind
```

## Installation

We're going to install it into `~/my_msvc` to avoid needing root privileges on a non-contained system.

```bash
# Download and unpack MSVC
./vsdownload.py --dest ~/my_msvc/opt/msvc
# Add wrapper scripts, do minor cleanup of the unpacked MSVC installation
./install.sh ~/my_msvc/opt/msvc

# Custom CMake
git clone https://gitlab.kitware.com/mstorsjo/cmake.git
cd cmake
git checkout 844ccd2280d11ada286d0e2547c0fa5ff22bd4db
mkdir build 
cd build
../configure --prefix=~/my_msvc/opt/cmake --parallel=$(nproc) -- -DCMAKE_USE_OPENSSL=OFF
make -j$(nproc)
make install

# Run wine at least once
wineserver -k # kills server (optional)
wineserver -p
wine64 wineboot
```

> **_Note:_** the installation path will be hardcoded in the installed `msvcenv.sh`, thus moving the folder to another location is not recommended.

### Setting up your project with CMake

You need to set the path to prioritize our custom CMake, and also to see our MSVC installation.
After that we just run CMake command with a few extra settings:

```bash
export PATH=~/my_msvc/opt/cmake/bin:$PATH
export PATH=~/my_msvc/opt/msvc/bin/x64:$PATH
CC=cl CXX=cl cmake .. -DCMAKE_BUILD_TYPE=Release -DBUILD_PROGRAMS=ON -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_CROSSCOMPILING=ON
make
```

# FAQ

## Does it run on Ubuntu 18.04 LTS?

Yes, but the install scripts won't work because `msitools` is too old. You'll need to install either via Docker or on a real Ubuntu 20.04 LTS machine; and later copy paste the files under `/opt/msvc`.

## Does it work with CMake?

Yes, but a custom version is needed or else CMake will complain that `/opt/msvc/bin/x64/cl` can't build a simple program.

It also fixes the `Ninja` Generator which otherwise has trouble finding RC.

## Can it build Debug versions?

Yes, but there may be troubles. From wine errors appearing in the logs/console to problems when trying to launch it because of missing debug redistributables.
You will also have to install winbind (see next item).

For the best out-of-the-box experience build in Release mode.

## fatal error C1902: Program database manager mismatch; please check your installation

You need winbind: `sudo apt install winbind`

Issue is [being tracked](https://github.com/mstorsjo/msvc-wine/issues/6).

## What generators work with CMake?

The following generators were tested and known to work:

 - Ninja
 - Unix Makefiles

Other generators are untested and may or may not work. Use it at your own peril.

## Do I _need_ CMake to use msvc-wine?

No. Using Ninja or GNU Make directly should work.

## I get `ninja: error: build.ninja:225: bad $-escape (literal $ must be written as $$)`

Visual Studio can switch between Debug/Release/RelWithDebInfo/etc at build time in the IDE.

It's slightly common for CMake projects to use `$(CONFIGURATION)` macro from Visual Studio to resolve commands to each intended configuration automatically.

However generators like `Ninja`/`Unix Makefiles` can only target one configuration at a time.

You'll have to edit the CMake script to use `${CMAKE_BUILD_TYPE}` instead when using `Ninja`/`Unix Makefiles` generators (which is extremely rare to use in an actual Windows environment).

Note the script may have other hardcoded commands which use `$(...)` syntax that make no sense when using generators other than Visual Studio; and will need to be fixed accordingly.

This is not an msvc-wine bug.
