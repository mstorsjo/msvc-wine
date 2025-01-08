Cross compilation with MSVC on Linux
====================================

This is a set of tools for using MSVC on Linux (and other Unix OSes).

It consists of two main parts:

- A Python script that downloads and unpacks MSVC and the Windows SDK

- Wrapping and tweaking of the unpacked MSVC/WinSDK to make MSVC work
  transparently from Unix based build tools with Wine

The first part also works without the second, as a source of MSVC
and WinSDK for use with e.g. clang-cl.

This downloads and unpacks the necessary Visual Studio components using
the same installer manifests as Visual Studio 2017/2019's installer
uses. Downloading and installing it requires accepting the license,
available at https://go.microsoft.com/fwlink/?LinkId=2086102 for the
currently latest version.

As Visual Studio isn't redistributable, the installed toolchain isn't
either.

To install, just run the following two commands:

    ./vsdownload.py --dest <dir>
    ./install.sh <dir>

The unpacking requires recent versions of msitools (0.98) and libgcab
(1.2); sufficiently new versions are available in e.g. Ubuntu 19.04.

After installing the toolchain this way, there are 4 directories with tools,
in `<dest>/bin/<arch>`, for all architectures out of `x86`,
`x64`, `arm` and `arm64`, that should be added to the PATH before building
with it.

There's also a reproducible dockerfile, that creates a docker image with
the MSVC tools available in `/opt/msvc`. (This also serves as a testable
example of an environment where the install is known to work.)


# Build instructions for local installation

The following instructions are for setting up MSVC without docker.

## Prerequisites

```bash
apt-get update
apt-get install -y wine64 python3 msitools ca-certificates winbind
```

## Installation

We're going to install it into `~/my_msvc` to avoid needing root privileges on a non-contained system.

```bash
# Download and unpack MSVC
./vsdownload.py --dest ~/my_msvc/opt/msvc
# Add wrapper scripts, do minor cleanup of the unpacked MSVC installation
./install.sh ~/my_msvc/opt/msvc

# Optional: Start a persistent wineserver
wineserver -k # Kill a potential old server
wineserver -p # Start a new server
wine64 wineboot # Run a process to start up all background wine processes
```

### Setting up your project with CMake

You need to add the our MSVC installation to the path.
After that we just run CMake command with a few extra settings:

```bash
export PATH=~/my_msvc/opt/msvc/bin/x64:$PATH
CC=cl CXX=cl cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_SYSTEM_NAME=Windows
make
```

# Use with Clang/LLD in MSVC mode

It's possible to cross compile from Linux using Clang and LLD operating entirely in MSVC mode, without running
any tools through Wine. This still requires the nonredistributable MSVC and WinSDK headers and libraries - which
can be fetched and unpacked conveniently with msvc-wine.

To use clang/lld with MSVC/WinSDK headers provided by msvc-wine, first download and set up the MSVC installation
as usual. You need less prerequisites as wine won't be needed:

```bash
apt-get update
apt-get install -y python3 msitools ca-certificates

# Download and unpack MSVC
./vsdownload.py --dest ~/my_msvc
# Clean up headers, add scripts for setting up the environments
./install.sh ~/my_msvc
```

To let Clang/LLD find the headers and libraries, source the `msvcenv-native.sh` script to set up the `INCLUDE`
and `LIB` environment variables, with the `BIN` variable pointing at the relevant `bin` directory set up by
`install.sh` above.

```bash
BIN=~/my_msvc/bin/x64 . ./msvcenv-native.sh
```

After this, you can invoke `clang-cl`, `clang --target=<arch>-windows-msvc` or `lld-link` without needing to
point it specifically towards the MSVC installation, e.g. like this:

```bash
clang-cl -c hello.c
lld-link hello.obj -out:hello.exe

clang --target=x86_64-windows-msvc hello.c -fuse-ld=lld -o hello.exe
```

This should work with most distributions of Clang (both upstream release packages and Linux distribution provided
packages). Note that not all distributions provide the clang-cl frontend (or it may exist as a version-suffixed
tool like `clang-cl-14`). If `clang-cl` or `lld-link` are unavailable but plain `clang` and `lld` (or `ld.lld`)
binaries are available, it's enough to just create new symlinks named `clang-cl` and `lld-link` pointing at
the existing binaries. (The binaries normally contain all support for all targets, but switch mode/behaviour based
on what name they are invoked as.)

Do note that older versions of Clang/LLD might not work out of the box with the libraries from the very latest
MSVC/WinSDK. Currently, at least Clang/LLD 13 seems to be required for MSVC 2019 16.8 or newer.

# FAQ

## Does it run on Ubuntu 18.04 LTS?

Yes, but the install scripts won't work because `msitools` is too old. You'll need to install either via Docker or on a real Ubuntu 20.04 LTS machine; and later copy paste the files under `/opt/msvc`.

## Does it run on Windows?

Yes, after downloading with the script, no further installation is required:
```cmd
python vsdownload.py --accept-license --dest C:\msvc
```

To set up the developer command prompt, run one of the `vcvars` batch files from Windows CMD, for example:
```cmd
call C:\msvc\VC\Auxiliary\Build\vcvars64.bat
```

If you are using [VSCode CMake Tools](https://aka.ms/vscode-cmake-tools), you can add a [kit](https://github.com/microsoft/vscode-cmake-tools/blob/main/docs/kits.md) as shown below:
```json
  {
    "name": "MSVC x64",
    "vendor": "MSVC",
    "compilers": {
      "C": "cl",
      "CXX": "cl"
    },
    "environmentSetupScript": "C:\\msvc\\VC\\Auxiliary\\Build\\vcvars64.bat",
    "preferredGenerator": {
      "name": "Ninja"
    },
    "isTrusted": true,
    "keep": true
  }
```

## Does it work with CMake?

Yes, but you need CMake 3.23, and either need `winbind` installed, or
need to configure the build to always use embedded debug info (or a
custom build of CMake that doesn't try to use separate PDB file debug
info by default).

Even if configuring CMake with `-DCMAKE_BUILD_TYPE=Release`, CMake does
call the compiler in `Debug` mode when it does the first few test
invocations of the compiler. By default, CMake uses separate PDB
file debug info, when compiling in `Debug` mode, i.e. using the
`/Zi` compiler option (as opposed to the `/Z7` option, storing the
debug info in the individual object files).

When MSVC is invoked with the `/Zi` and `/FS` options, it spawns a
background `mspdbsrv.exe` process and communicates with it. This
requires the `winbind` package to be installed for this communication
to work.

With CMake 3.25, it's possible to override the type of debug info
even for the first few probing steps. This requires the CMake project
to either set `cmake_minimum_required(VERSION 3.25.0)`, or set
`cmake_policy(SET CMP0141 NEW)`, and requires the user to configure it
with `-DCMAKE_MSVC_DEBUG_INFORMATION_FORMAT=Embedded`; in such a
configuration, `winbind` isn't needed.

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

## How to integrate with vcpkg?

On Windows, you just define the two environment variables before invoking `vcpkg`:
```cmd
set VS170COMNTOOLS=C:\msvc\Common7\Tools\
set VCPKG_VISUAL_STUDIO_PATH=C:\msvc
```

On Unix, you need define your own triplets, e.g. `my-triplets/x64-windows.cmake`:
```cmake
set(VCPKG_TARGET_ARCHITECTURE x64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE dynamic)
set(VCPKG_CHAINLOAD_TOOLCHAIN_FILE ${VCPKG_ROOT_DIR}/scripts/toolchains/windows.cmake)

set(ENV{CC} cl.exe)
set(ENV{CXX} cl.exe)
set(ENV{PATH} "/opt/msvc/bin/x64:$ENV{PATH}")
```

Then you can install packages using overlay triplets:
```bash
vcpkg install sqlite3:x64-windows --overlay-triplets=my-triplets
```
See examples [here](test/test-vcpkg.sh).

## I get `ninja: error: build.ninja:225: bad $-escape (literal $ must be written as $$)`

Visual Studio can switch between Debug/Release/RelWithDebInfo/etc at build time in the IDE.

It's slightly common for CMake projects to use `$(CONFIGURATION)` macro from Visual Studio to resolve commands to each intended configuration automatically.

However generators like `Ninja`/`Unix Makefiles` can only target one configuration at a time.

You'll have to edit the CMake script to use `${CMAKE_BUILD_TYPE}` instead when using `Ninja`/`Unix Makefiles` generators (which is extremely rare to use in an actual Windows environment).

Note the script may have other hardcoded commands which use `$(...)` syntax that make no sense when using generators other than Visual Studio; and will need to be fixed accordingly.

This is not an msvc-wine bug.
