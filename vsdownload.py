#!/usr/bin/env python3
#
# Copyright (c) 2019 Martin Storsjo
#
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

import argparse
import functools
import glob
import hashlib
import os
import json
import platform
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import urllib.request
import xml.etree.ElementTree as ET
import zipfile
from concurrent.futures import ThreadPoolExecutor

class ThreadPool:
    def __init__(self, workers=None):
        self._executor = ThreadPoolExecutor(max_workers=workers)

    class _AsyncResult:
        def __init__(self, fut):
            self._fut = fut
        def get(self, timeout=None):
            return self._fut.result(timeout)
        def wait(self, timeout=None):
            self._fut.result(timeout)

    def apply_async(self, func, args=(), kwds=None, callback=None):
        fut = self._executor.submit(func, *(args or ()), **(kwds or {}))
        if callback:
            fut.add_done_callback(lambda f: callback(f.result()))
        return self._AsyncResult(fut)

    def map(self, func, iterable):
        return list(self._executor.map(func, iterable))

    def close(self):
        pass

    def join(self):
        self._executor.shutdown(wait=True)

    def terminate(self):
        self._executor.shutdown(cancel_futures=True)

def getArgsParser():
    class OptionalBoolean(argparse.Action):
        def __init__(self,
                    option_strings,
                    dest,
                    default=None,
                    help=None):

            if default is not None:
                default_string = "yes" if default else "no"
                if help is None:
                    help = "default: " + default_string
                else:
                    help += " (default: %s)" % default_string

            super().__init__(
                option_strings=option_strings,
                dest=dest,
                nargs='?',
                default=default,
                choices=["yes", "no"],
                help=help,
                metavar="yes|no")

        def __call__(self, parser, namespace, values, option_string=None):
            setattr(namespace, self.dest, values != "no")

    parser = argparse.ArgumentParser(description = "Download and install Visual Studio")
    parser.add_argument("--manifest", metavar="manifest", help="A predownloaded manifest file")
    parser.add_argument("--save-manifest", const=True, action="store_const", help="Store the downloaded manifest to a file")
    parser.add_argument("--major", default=17, type=int, metavar="version", help="The major version to download (defaults to 17)")
    parser.add_argument("--preview", const=True, action="store_const", help="Download the preview version instead of the release version")
    parser.add_argument("--cache", metavar="dir", help="Directory to use as a persistent cache for downloaded files")
    parser.add_argument("--dest", metavar="dir", help="Directory to install into")
    parser.add_argument("package", metavar="package", help="Package to install. If omitted, installs the default command line tools.", nargs="*")
    parser.add_argument("--ignore", metavar="component", help="Package to skip", action="append")
    parser.add_argument("--accept-license", const=True, action="store_const", help="Don't prompt for accepting the license")
    parser.add_argument("--print-version", const=True, action="store_const", help="Stop after fetching the manifest")
    parser.add_argument("--list-workloads", const=True, action="store_const", help="List high level workloads")
    parser.add_argument("--list-components", const=True, action="store_const", help="List available components")
    parser.add_argument("--list-packages", const=True, action="store_const", help="List all individual packages, regardless of type")
    parser.add_argument("--include-optional", const=True, action="store_const", help="Include all optional dependencies")
    parser.add_argument("--skip-recommended", const=True, action="store_const", help="Don't include recommended dependencies")
    parser.add_argument("--print-deps-tree", const=True, action="store_const", help="Print a tree of resolved dependencies for the given selection")
    parser.add_argument("--print-reverse-deps", const=True, action="store_const", help="Print a tree of packages that depend on the given selection")
    parser.add_argument("--print-selection", const=True, action="store_const", help="Print a list of the individual packages that are selected to be installed")
    parser.add_argument("--only-download", const=True, action="store_const", help="Stop after downloading package files")
    parser.add_argument("--only-unpack", const=True, action="store_const", help="Unpack the selected packages and keep all files, in the layout they are unpacked, don't restructure and prune files other than what's needed for MSVC CLI tools")
    parser.add_argument("--keep-unpack", const=True, action="store_const", help="Keep the unpacked files that aren't otherwise selected as needed output")
    parser.add_argument("--msvc-version", metavar="version", help="Install a specific MSVC toolchain version")
    parser.add_argument("--sdk-version", metavar="version", help="Install a specific Windows SDK version")
    parser.add_argument("--architecture", metavar="arch", choices=["host", "x86", "x64", "arm", "arm64"], help="Target architectures to include (defaults to all)", nargs="+")
    parser.add_argument("--with-wdk-installers", metavar="dir", help="Install Windows Driver Kit using the provided MSI installers")
    parser.add_argument("--host-arch", metavar="arch", choices=["x86", "x64", "arm64"], help="Specify the host architecture of packages to install")
    parser.add_argument("--only-host", default=True, action=OptionalBoolean, help="Only download packages that match host arch")
    parser.add_argument("--skip-patch", action="store_true", help="Don't patch downloaded packages")
    return parser

def setPackageSelectionMSVC16(args, packages, userversion, sdk, toolversion, defaultPackages):
    if findPackage(packages, "Microsoft.VisualStudio.Component.VC." + toolversion + ".x86.x64", warn=False):
        if "x86" in args.architecture or "x64" in args.architecture:
            args.package.append("Microsoft.VisualStudio.Component.VC." + toolversion + ".x86.x64")
            args.package.append("Microsoft.VC." + toolversion + ".ASAN.X86")
            args.package.append("Microsoft.VisualStudio.Component.VC." + toolversion + ".ATL")
        if "arm" in args.architecture:
            args.package.append("Microsoft.VisualStudio.Component.VC." + toolversion + ".ARM")
            args.package.append("Microsoft.VisualStudio.Component.VC." + toolversion + ".ATL.ARM")
        if "arm64" in args.architecture:
            args.package.append("Microsoft.VisualStudio.Component.VC." + toolversion + ".ARM64")
            args.package.append("Microsoft.VisualStudio.Component.VC." + toolversion + ".ATL.ARM64")

        if args.sdk_version == None:
            args.sdk_version = sdk
    else:
        # Options for toolchains for specific versions. The latest version in
        # each manifest isn't available as a pinned version though, so if that
        # version is requested, try the default version.
        print("Didn't find exact version packages for " + userversion + ", assuming this is provided by the default/latest version")
        args.package.extend(defaultPackages)

def setPackageSelectionMSVC15(args, packages, userversion, sdk, toolversion, defaultPackages):
    if findPackage(packages, "Microsoft.VisualStudio.Component.VC.Tools." + toolversion, warn=False):
        args.package.extend(["Win10SDK_" + sdk, "Microsoft.VisualStudio.Component.VC.Tools." + toolversion])
    else:
        # Options for toolchains for specific versions. The latest version in
        # each manifest isn't available as a pinned version though, so if that
        # version is requested, try the default version.
        print("Didn't find exact version packages for " + userversion + ", assuming this is provided by the default/latest version")
        args.package.extend(defaultPackages)

def setPackageSelection(args, packages):
    if not args.architecture:
        args.architecture = ["host", "x86", "x64", "arm", "arm64"]
    if args.host_arch is not None and "host" in args.architecture:
        args.architecture.append(args.host_arch)

    # If no packages are selected, install these versionless packages, which
    # gives the latest/recommended version for the current manifest.
    defaultPackages = ["Microsoft.VisualStudio.Workload.VCTools"]
    if "x86" in args.architecture or "x64" in args.architecture:
        defaultPackages.append("Microsoft.VisualStudio.Component.VC.ATL")
    if "arm" in args.architecture:
        defaultPackages.append("Microsoft.VisualStudio.Component.VC.Tools.ARM")
        defaultPackages.append("Microsoft.VisualStudio.Component.VC.ATL.ARM")
    if "arm64" in args.architecture:
        defaultPackages.append("Microsoft.VisualStudio.Component.VC.Tools.ARM64")
        defaultPackages.append("Microsoft.VisualStudio.Component.VC.ATL.ARM64")

    # Note, that in the manifest for MSVC version X.Y, only version X.Y-1
    # exists with a package name like "Microsoft.VisualStudio.Component.VC."
    # + toolversion + ".x86.x64".
    if args.msvc_version == "16.0":
        setPackageSelectionMSVC16(args, packages, args.msvc_version, "10.0.17763", "14.20", defaultPackages)
    elif args.msvc_version == "16.1":
        setPackageSelectionMSVC16(args, packages, args.msvc_version, "10.0.18362", "14.21", defaultPackages)
    elif args.msvc_version == "16.2":
        setPackageSelectionMSVC16(args, packages, args.msvc_version, "10.0.18362", "14.22", defaultPackages)
    elif args.msvc_version == "16.3":
        setPackageSelectionMSVC16(args, packages, args.msvc_version, "10.0.18362", "14.23", defaultPackages)
    elif args.msvc_version == "16.4":
        setPackageSelectionMSVC16(args, packages, args.msvc_version, "10.0.18362", "14.24", defaultPackages)
    elif args.msvc_version == "16.5":
        setPackageSelectionMSVC16(args, packages, args.msvc_version, "10.0.18362", "14.25", defaultPackages)
    elif args.msvc_version == "16.6":
        setPackageSelectionMSVC16(args, packages, args.msvc_version, "10.0.18362", "14.26", defaultPackages)
    elif args.msvc_version == "16.7":
        setPackageSelectionMSVC16(args, packages, args.msvc_version, "10.0.18362", "14.27", defaultPackages)
    elif args.msvc_version == "16.8":
        setPackageSelectionMSVC16(args, packages, args.msvc_version, "10.0.18362", "14.28", defaultPackages)
    elif args.msvc_version == "16.9":
        setPackageSelectionMSVC16(args, packages, args.msvc_version, "10.0.19041", "14.28.16.9", defaultPackages)
    elif args.msvc_version == "16.10":
        setPackageSelectionMSVC16(args, packages, args.msvc_version, "10.0.19041", "14.29.16.10", defaultPackages)
    elif args.msvc_version == "16.11":
        setPackageSelectionMSVC16(args, packages, args.msvc_version, "10.0.19041", "14.29.16.11", defaultPackages)
    elif args.msvc_version == "17.0":
        setPackageSelectionMSVC16(args, packages, args.msvc_version, "10.0.19041", "14.30.17.0", defaultPackages)
    elif args.msvc_version == "17.1":
        setPackageSelectionMSVC16(args, packages, args.msvc_version, "10.0.19041", "14.31.17.1", defaultPackages)
    elif args.msvc_version == "17.2":
        setPackageSelectionMSVC16(args, packages, args.msvc_version, "10.0.19041", "14.32.17.2", defaultPackages)
    elif args.msvc_version == "17.3":
        setPackageSelectionMSVC16(args, packages, args.msvc_version, "10.0.19041", "14.33.17.3", defaultPackages)
    elif args.msvc_version == "17.4":
        setPackageSelectionMSVC16(args, packages, args.msvc_version, "10.0.22621", "14.34.17.4", defaultPackages)
    elif args.msvc_version == "17.5":
        setPackageSelectionMSVC16(args, packages, args.msvc_version, "10.0.22621", "14.35.17.5", defaultPackages)
    elif args.msvc_version == "17.6":
        setPackageSelectionMSVC16(args, packages, args.msvc_version, "10.0.22621", "14.36.17.6", defaultPackages)
    elif args.msvc_version == "17.7":
        setPackageSelectionMSVC16(args, packages, args.msvc_version, "10.0.22621", "14.37.17.7", defaultPackages)
    elif args.msvc_version == "17.8":
        setPackageSelectionMSVC16(args, packages, args.msvc_version, "10.0.22621", "14.38.17.8", defaultPackages)
    elif args.msvc_version == "17.9":
        setPackageSelectionMSVC16(args, packages, args.msvc_version, "10.0.22621", "14.39.17.9", defaultPackages)
    elif args.msvc_version == "17.10":
        setPackageSelectionMSVC16(args, packages, args.msvc_version, "10.0.22621", "14.40.17.10", defaultPackages)
    elif args.msvc_version == "17.11":
        setPackageSelectionMSVC16(args, packages, args.msvc_version, "10.0.22621", "14.41.17.11", defaultPackages)
    elif args.msvc_version == "17.12":
        setPackageSelectionMSVC16(args, packages, args.msvc_version, "10.0.22621", "14.42.17.12", defaultPackages)
    elif args.msvc_version == "17.13":
        setPackageSelectionMSVC16(args, packages, args.msvc_version, "10.0.22621", "14.43.17.13", defaultPackages)
    elif args.msvc_version == "17.14":
        setPackageSelectionMSVC16(args, packages, args.msvc_version, "10.0.26100", "14.44.17.14", defaultPackages)
    elif args.msvc_version == "18.0":
        setPackageSelectionMSVC16(args, packages, args.msvc_version, "10.0.26100", "14.50.18.0", defaultPackages)

    elif args.msvc_version == "15.4":
        setPackageSelectionMSVC15(args, packages, args.msvc_version, "10.0.16299", "14.11", defaultPackages)
    elif args.msvc_version == "15.5":
        setPackageSelectionMSVC15(args, packages, args.msvc_version, "10.0.16299", "14.12", defaultPackages)
    elif args.msvc_version == "15.6":
        setPackageSelectionMSVC15(args, packages, args.msvc_version, "10.0.16299", "14.13", defaultPackages)
    elif args.msvc_version == "15.7":
        setPackageSelectionMSVC15(args, packages, args.msvc_version, "10.0.17134", "14.14", defaultPackages)
    elif args.msvc_version == "15.8":
        setPackageSelectionMSVC15(args, packages, args.msvc_version, "10.0.17134", "14.15", defaultPackages)
    elif args.msvc_version == "15.9":
        setPackageSelectionMSVC15(args, packages, args.msvc_version, "10.0.17763", "14.16", defaultPackages)
    elif args.msvc_version != None:
        print("Unsupported MSVC toolchain version " + args.msvc_version)
        sys.exit(1)

    if len(args.package) == 0:
        args.package = defaultPackages

    if args.sdk_version != None:
        found = False
        versions = []
        for key in packages:
            if key.startswith("win10sdk") or key.startswith("win11sdk"):
                base = key[0:8]
                version = key[9:]
                if re.match(r'\d+\.\d+\.\d+', version):
                    versions += [version]
                sdkname = base + "_" + args.sdk_version
                if key == sdkname:
                    found = True
                    args.package.append(key)
                else:
                    args.ignore.append(key)
        if not found:
            print("WinSDK version " + args.sdk_version + " not found")
            print("Available versions:")
            for v in sorted(versions):
                print("    " + v)
            sys.exit(1)

    if args.with_wdk_installers is not None:
        args.package.append("Component.Microsoft.Windows.DriverKit.BuildTools")

def lowercaseIgnores(args):
    ignore = []
    if args.ignore != None:
        for i in args.ignore:
            ignore.append(i.lower())
    args.ignore = ignore

def getManifest(args):
    if args.manifest == None:
        type = "release"
        if args.preview:
            if args.major < 18:
                type = "pre"
            else:
                type = "insiders"
        url = "https://aka.ms/vs/%s/%s/channel" % (args.major, type)
        print("Fetching %s" % (url))
        manifest = json.loads(urllib.request.urlopen(url).read())
        print("Got toplevel manifest for %s" % (manifest["info"]["productDisplayVersion"]))
        for item in manifest["channelItems"]:
            if "type" in item and item["type"] == "Manifest":
                args.manifest = item["payloads"][0]["url"]
        if args.manifest == None:
            print("Unable to find an intaller manifest!")
            sys.exit(1)

    if not args.manifest.startswith("http"):
        args.manifest = "file:" + args.manifest

    manifestdata = urllib.request.urlopen(args.manifest).read()
    manifest = json.loads(manifestdata)
    print("Loaded installer manifest for %s" % (manifest["info"]["productDisplayVersion"]))

    if args.save_manifest:
        filename = "%s.manifest" % (manifest["info"]["productDisplayVersion"])
        if os.path.isfile(filename):
            oldfile = open(filename, "rb").read()
            if oldfile != manifestdata:
                print("Old saved manifest in \"%s\" differs from newly downloaded one, not overwriting!" % (filename))
            else:
                print("Old saved manifest in \"%s\" is still current" % (filename))
        else:
            f = open(filename, "wb")
            f.write(manifestdata)
            f.close()
            print("Saved installer manifest to \"%s\"" % (filename))

    return manifest

def prioritizePackage(arch, a, b):
    def archOrd(k, x):
        if arch is None:
            return 0
        c = x.get(k, "neutral").lower()
        if c == "neutral":
            return 0
        if c == arch:
            return -1
        return 1

    for k in ["chip", "machineArch", "productArch"]:
        r = archOrd(k, a) - archOrd(k, b)
        if r != 0:
            return r

    if "language" in a and "language" in b:
        aeng = a["language"].lower().startswith("en-")
        beng = b["language"].lower().startswith("en-")
        if aeng and not beng:
            return -1
        if beng and not aeng:
            return 1
    return 0

def getPackages(manifest, arch):
    packages = {}
    for p in manifest["packages"]:
        id = p["id"].lower()
        if not id in packages:
            packages[id] = []
        packages[id].append(p)
    for key in packages:
        packages[key] = sorted(packages[key], key=functools.cmp_to_key(functools.partial(prioritizePackage, arch)))
    return packages

def listPackageType(packages, type):
    if type != None:
        type = type.lower()
    ids = []
    for key in packages:
        p = packages[key][0]
        if type == None:
            ids.append(p["id"])
        elif "type" in p and p["type"].lower() == type:
            ids.append(p["id"])
    for id in sorted(ids):
        print(id)

def findPackage(packages, id, constraints={}, warn=True):
    origid = id
    id = id.lower()
    candidates = None
    if not id in packages:
        if warn:
            print("WARNING: %s not found" % (origid))
        return None
    candidates = packages[id]
    for a in candidates:
        matched = True
        for k, v in constraints.items():
            if k in ["chip", "machineArch"]:
                matched = a.get(k, "").lower() == v.lower()
                if not matched:
                    break
        if matched:
            return a
    return candidates[0]

def matchPackageHostArch(p, host):
    if host is None:
        return True

    known_archs = ["x86", "x64", "arm64"]

    # Some packages have host arch in their ids, e.g.
    # - Microsoft.VisualCpp.Tools.HostARM64.TargetX64
    # - Microsoft.VisualCpp.Tools.HostX64.TargetX64
    id = p["id"].lower()
    for a in known_archs:
        if "host" + a in id:
            return a == host

    for k in ["chip", "machineArch", "productArch"]:
        a = p.get(k, "neutral").lower()
        if a == "neutral":
            continue
        if a != host:
            return False

    return True

def matchPackageTargetArch(p, archs):
    if archs is None:
        return True

    known_archs = ["x86", "x64", "arm", "arm64"]

    # Some packages have target arch in their ids, e.g.
    # - Microsoft.VisualCpp.Tools.HostARM64.TargetX64
    # - Microsoft.VisualCpp.Tools.HostX64.TargetX64
    id = p["id"].lower()
    for a in known_archs:
        if re.search(fr"\.target{a}(\W|$)", id):
            return a in archs

    return True

def printDepends(packages, target, constraints, indent, args):
    chipstr = ""
    for k in ["chip", "machineArch"]:
        v = constraints.get(k)
        if v is not None:
            chipstr = chipstr + " (" + k + "." + v + ")"
    deptypestr = ""
    deptype = constraints.get("type", "")
    if deptype != "":
        deptypestr = " (" + deptype + ")"
    ignorestr = ""
    ignore = False
    if target.lower() in args.ignore:
        ignorestr = " (Ignored)"
        ignore = True
    if deptype == "Optional" and not args.include_optional:
        ignore = True
    if deptype == "Recommended" and args.skip_recommended:
        ignore = True
    if not ignore:
        p = findPackage(packages, target, constraints, warn=False)
        if p == None:
            ignorestr = " (NotFound)"
            ignore = True
        elif args.only_host and not matchPackageHostArch(p, args.host_arch):
            ignorestr = " (HostArchMismatch)"
            ignore = True
        elif not matchPackageTargetArch(p, args.architecture):
            ignorestr = " (TargetArchMismatch)"
            ignore = True
    print(indent + target + chipstr + deptypestr + ignorestr)
    if ignore:
        return
    for target, constraints in p.get("dependencies", {}).items():
        if not isinstance(constraints, dict):
            constraints = { "version": constraints }
        target = constraints.get("id", target)
        printDepends(packages, target, constraints, indent + "  ", args)

def printReverseDepends(packages, target, deptype, indent, args):
    deptypestr = ""
    if deptype != "":
        deptypestr = " (" + deptype + ")"
    print(indent + target + deptypestr)
    if deptype == "Optional" and not args.include_optional:
        return
    if deptype == "Recommended" and args.skip_recommended:
        return
    target = target.lower()
    for key in packages:
        p = packages[key][0]
        if "dependencies" in p:
            deps = p["dependencies"]
            for k in deps:
                if k.lower() != target:
                    continue
                dep = deps[k]
                type = ""
                if "type" in dep:
                    type = dep["type"]
                printReverseDepends(packages, p["id"], type, indent + "  ", args)

def getPackageKey(p):
    packagekey = p["id"]
    if "version" in p:
        packagekey = packagekey + "-" + p["version"]
    for k in ["chip", "machineArch", "productArch"]:
        v = p.get(k)
        if v is not None:
           packagekey = packagekey + "-" + k + "." + v
    return packagekey

def aggregateDepends(packages, included, target, constraints, args):
    if target.lower() in args.ignore:
        return []
    p = findPackage(packages, target, constraints)
    if p == None:
        return []
    if args.only_host and not matchPackageHostArch(p, args.host_arch):
        return []
    if not matchPackageTargetArch(p, args.architecture):
        return []
    packagekey = getPackageKey(p)
    if packagekey in included:
        return []
    ret = [p]
    included[packagekey] = True
    for target, constraints in p.get("dependencies", {}).items():
        if not isinstance(constraints, dict):
            constraints = { "version": constraints }
        target = constraints.get("id", target)
        deptype = constraints.get("type")
        if deptype == "Optional" and not args.include_optional:
            continue
        if deptype == "Recommended" and args.skip_recommended:
            continue
        ret.extend(aggregateDepends(packages, included, target, constraints, args))
    return ret

def getSelectedPackages(packages, args):
    ret = []
    included = {}
    for i in args.package:
        ret.extend(aggregateDepends(packages, included, i, {}, args))
    return ret

def sumInstalledSize(l):
    sum = 0
    for p in l:
        if "installSizes" in p:
            sizes = p["installSizes"]
            for location in sizes:
                sum = sum + sizes[location]
    return sum

def sumDownloadSize(l):
    sum = 0
    for p in l:
        if "payloads" in p:
            for payload in p["payloads"]:
                if "size" in payload:
                    sum = sum + payload["size"]
    return sum

def formatSize(s):
    if s > 900*1024*1024:
        return "%.1f GB" % (s/(1024*1024*1024))
    if s > 900*1024:
        return "%.1f MB" % (s/(1024*1024))
    if s > 1024:
        return "%.1f KB" % (s/1024)
    return "%d bytes" % (s)

def printPackageList(l):
    for p in sorted(l, key=lambda p: p["id"]):
        s = p["id"]
        if "type" in p:
            s = s + " (" + p["type"] + ")"
        for k in ["chip", "machineArch", "productArch"]:
            v = p.get(k)
            if v is not None:
                s = s + " (" + k + "." + v + ")"
        if "language" in p:
            s = s + " (" + p["language"] + ")"
        s = s + " " + formatSize(sumInstalledSize([p]))
        print(s)

def makedirs(dir):
    try:
        os.makedirs(dir)
    except OSError:
        pass

def sha256File(file):
    sha256Hash = hashlib.sha256()
    with open(file, "rb") as f:
        for byteBlock in iter(lambda: f.read(4096), b""):
                sha256Hash.update(byteBlock)
        return sha256Hash.hexdigest()

def getPayloadName(payload):
    name = payload["fileName"]
    if "\\" in name:
        name = name.split("\\")[-1]
    if "/" in name:
        name = name.split("/")[-1]
    return name

def downloadPackages(selected, cache, allowHashMismatch = False):
    pool = ThreadPool(5)
    tasks = []
    makedirs(cache)
    for p in selected:
        if not "payloads" in p:
            continue
        dir = os.path.join(cache, getPackageKey(p))
        makedirs(dir)
        for payload in p["payloads"]:
            name = getPayloadName(payload)
            destname = os.path.join(dir, name)
            fileid = os.path.join(getPackageKey(p), name)
            args = (payload, destname, fileid, allowHashMismatch)
            tasks.append(pool.apply_async(_downloadPayload, args))

    downloaded = sum(task.get() for task in tasks)
    pool.close()
    print("Downloaded %s in total" % (formatSize(downloaded)))

def _downloadPayload(payload, destname, fileid, allowHashMismatch):
    attempts = 5
    for attempt in range(attempts):
        try:
            if os.access(destname, os.F_OK):
                if "sha256" in payload:
                    if sha256File(destname).lower() != payload["sha256"].lower():
                        print("Incorrect existing file %s, removing" % (fileid), flush=True)
                        os.remove(destname)
                    else:
                        print("Using existing file %s" % (fileid), flush=True)
                        return 0
                else:
                    return 0
            size = 0
            if "size" in payload:
                size = payload["size"]
            print("Downloading %s (%s)" % (fileid, formatSize(size)), flush=True)
            urllib.request.urlretrieve(payload["url"], destname)
            if "sha256" in payload:
                if sha256File(destname).lower() != payload["sha256"].lower():
                    if allowHashMismatch:
                        print("WARNING: Incorrect hash for downloaded file %s" % (fileid), flush=True)
                    else:
                        raise Exception("Incorrect hash for downloaded file %s, aborting" % fileid)
            return size
        except Exception as e:
            if attempt == attempts - 1:
                raise
            print("%s: %s" % (type(e).__name__, e), flush=True)

def mergeTrees(src, dest):
    if not os.path.isdir(src):
        return
    if not os.path.isdir(dest):
        shutil.move(src, dest)
        return
    names = os.listdir(src)
    destnames = {}
    for n in os.listdir(dest):
        destnames[n.lower()] = n
    for n in names:
        srcname = os.path.join(src, n)
        destname = os.path.join(dest, n)
        if os.path.isdir(srcname):
            if os.path.isdir(destname):
                mergeTrees(srcname, destname)
            elif n.lower() in destnames:
                mergeTrees(srcname, os.path.join(dest, destnames[n.lower()]))
            else:
                shutil.move(srcname, destname)
        else:
            shutil.move(srcname, destname)

def unzipFiltered(zip, dest):
    tmp = os.path.join(dest, "extract")
    for f in zip.infolist():
        name = urllib.parse.unquote(f.filename)
        if "/" in name:
            sep = name.rfind("/")
            dir = os.path.join(dest, name[0:sep])
            makedirs(dir)
        extracted = zip.extract(f, tmp)
        shutil.move(extracted, os.path.join(dest, name))
    shutil.rmtree(tmp)

def unpackVsix(file, dest, listing):
    temp = os.path.join(dest, "vsix")
    makedirs(temp)
    with zipfile.ZipFile(file, "r") as zip:
        unzipFiltered(zip, temp)
        with open(listing, "w") as f:
            for n in zip.namelist():
                f.write(n + "\n")
    contents = os.path.join(temp, "Contents")
    if os.access(contents, os.F_OK):
        mergeTrees(contents, dest)
    # This archive directory structure is used in WDK.vsix.
    msbuild = os.path.join(temp, "$MSBuild")
    if os.access(msbuild, os.F_OK):
        mergeTrees(msbuild, os.path.join(dest, "MSBuild"))
    shutil.rmtree(temp)

def unpackWin10SDK(src, payloads, dest):
    # We could try to unpack only the MSIs we need here.
    # Note, this extracts some files into Program Files/..., and some
    # files directly in the root unpack directory. The files we need
    # are under Program Files/... though.
    # On Windows, msiexec extracts files to the root unpack directory.
    # To be consistent, symlink Program Files to root.
    if sys.platform != "win32" and not os.access(os.path.join(dest, "Program Files"), os.F_OK):
        os.symlink(".", os.path.join(dest, "Program Files"), target_is_directory=True)

    for payload in payloads:
        name = getPayloadName(payload)
        if name.endswith(".msi"):
            print("Extracting " + name)
            srcfile = os.path.join(src, name)
            if sys.platform == "win32":
                # The path to TARGETDIR need to be quoted in the case of spaces.
                cmd = "msiexec /a \"%s\" /qn TARGETDIR=\"%s\"" % (srcfile, os.path.abspath(dest))
            else:
                cmd = ["msiextract", "-C", dest, srcfile]
            with open(os.path.join(dest, "WinSDK-" + getPayloadName(payload) + "-listing.txt"), "w") as log:
                subprocess.check_call(cmd, stdout=log)

def unpackWin10WDK(src, dest):
    print("Unpacking WDK installers from", src)

    # WDK installers downloaded by wdksetup.exe include a huge pile of
    # non-WDK installers, just skip these.
    for srcfile in glob.glob(src + "/Windows Driver*.msi"):
        name = os.path.basename(srcfile)
        print("Extracting", name)

        # Do not try to run msiexec here because TARGETDIR
        # does not work with WDK installers.
        cmd = ["msiextract", "-C", dest, srcfile]

        payloadName, _ = os.path.splitext(name)
        with open(os.path.join(dest, "WDK-" + payloadName + "-listing.txt"), "w") as log:
            subprocess.check_call(cmd, stdout=log)

    # WDK includes a VS extension, unpack it before copying the extracted files.
    for vsix in glob.glob(dest + "/**/WDK.vsix", recursive=True):
        name = os.path.basename(vsix)
        print("Unpacking WDK VS extension", name)

        payloadName, _ = os.path.splitext(name)
        listing = os.path.join(dest, "WDK-VS-" + payloadName + "-listing.txt")
        unpackVsix(vsix, dest, listing)

    # Merge incorrectly extracted 'Build' and 'build' directory trees.
    # The WDK 'build' tree must be versioned.
    kitsPath = os.path.join(dest, "Program Files", "Windows Kits", "10")
    brokenBuildDir = os.path.join(kitsPath, "Build")
    for buildDir in glob.glob(kitsPath + "/build/10.*/"):
        wdkVersion = buildDir.split("/")[-2];
        print("Merging WDK 'Build' and 'build' directories into version", wdkVersion);
        mergeTrees(brokenBuildDir, buildDir)
    shutil.rmtree(brokenBuildDir)

    # Move the WDK .props files into a versioned directory.
    propsPath = os.path.join(kitsPath, "DesignTime", "CommonConfiguration", "Neutral", "WDK");
    versionedPath = os.path.join(propsPath, wdkVersion)
    makedirs(versionedPath)
    for props in glob.glob(propsPath + "/*.props"):
        filename = os.path.basename(props)
        print("Moving", filename, "into version", wdkVersion);
        shutil.move(props, os.path.join(versionedPath, filename))

def extractPackages(selected, cache, dest):
    makedirs(dest)
    # The path name casing is not consistent across packages, or even within a single package.
    # Manually create top-level folders before extracting packages to ensure the desired casing.
    makedirs(os.path.join(dest, "MSBuild"))
    for p in selected:
        type = p["type"]
        dir = os.path.join(cache, getPackageKey(p))
        if type == "Component" or type == "Workload" or type == "Group":
            continue
        if type == "Vsix":
            print("Unpacking " + p["id"])
            for payload in p["payloads"]:
                unpackVsix(os.path.join(dir, getPayloadName(payload)), dest, os.path.join(dest, getPackageKey(p) + "-listing.txt"))
        elif p["id"].startswith("Win10SDK") or p["id"].startswith("Win11SDK"):
            print("Unpacking " + p["id"])
            unpackWin10SDK(dir, p["payloads"], dest)
        else:
            print("Skipping unpacking of " + p["id"] + " of type " + type)

def patchPackages(dest):
    patches = os.path.join(os.path.dirname(os.path.abspath(__file__)), "patches")
    if not os.path.isdir(patches):
        return
    for patch in glob.iglob(os.path.join(patches, "**"), recursive=True):
        if os.path.isdir(patch):
            continue
        p = os.path.relpath(patch, patches)
        f, op = os.path.splitext(p)
        if op == ".patch":
            if os.access(os.path.join(dest, f), os.F_OK):
                # Check if the patch has already been applied by attempting a reverse application; skip if already applied.
                if subprocess.call(["git", "--work-tree=.", "apply", "--quiet", "--reverse", "--check", patch], cwd=dest) != 0:
                    print("Patching " + f)
                    subprocess.check_call(["git", "--work-tree=.", "apply", patch], cwd=dest)
        elif op == ".remove":
            if os.access(os.path.join(dest, f), os.F_OK):
                print("Removing " + f)
                os.remove(os.path.join(dest, f))
        else:
            print("Copying " + p)
            os.makedirs(os.path.dirname(os.path.join(dest, p)), exist_ok=True)
            shutil.copyfile(patch, os.path.join(dest, p))

def copyDependentAssemblies(app):
    if not os.path.isfile(app + ".config"):
        return
    dest = os.path.dirname(app)
    ns = "{urn:schemas-microsoft-com:asm.v1}"
    configuration = ET.parse(app + ".config")
    for codeBase in configuration.findall(f"./runtime/{ns}assemblyBinding/{ns}dependentAssembly/{ns}codeBase/[@href]"):
        href = codeBase.attrib["href"].replace("\\", "/")
        src = os.path.join(dest, href)
        if os.path.isfile(src):
            shutil.copy(src, dest)

def moveVCSDK(unpack, dest):
    # Move some components out from the unpack directory,
    # allowing the rest of unpacked files to be removed.
    components = [
        "VC",
        "Windows Kits",
        # The DIA SDK isn't necessary for normal use, but can be used when e.g.
        # compiling LLVM.
        "DIA SDK",
        # MSBuild is the standard VC build tool.
        "MSBuild",
        # This directory contains batch scripts to setup Developer Command Prompt.
        # Environment variable VS170COMNTOOLS points to this directory, and some
        # tools use it to locate VS installation root and MSVC toolchains.
        os.path.join("Common7", "Tools"),
    ]
    for dir in filter(None, components):
        mergeTrees(os.path.join(unpack, dir), os.path.join(dest, dir))

if __name__ == "__main__":
    parser = getArgsParser()
    args = parser.parse_args()
    lowercaseIgnores(args)

    socket.setdefaulttimeout(15)

    if args.host_arch is None:
        args.host_arch = platform.machine().lower()
        if platform.system() == "Darwin":
            # There is no prebuilt arm64 Wine on macOS.
            args.host_arch = "x64"
        elif args.host_arch in ["x86", "i386", "i686"]:
            args.host_arch = "x86"
        elif args.host_arch in ["x64", "x86_64", "amd64"]:
            args.host_arch = "x64"
        elif args.host_arch in ["arm64", "aarch64"]:
            args.host_arch = "arm64"
        else:
            args.host_arch = None

    if args.host_arch is None:
        print("WARNING: Unable to detect host architecture")
    else:
        print("Install packages for %s host architecture" % args.host_arch)

    packages = getPackages(getManifest(args), args.host_arch)

    if args.print_version:
        sys.exit(0)

    if not args.accept_license:
        response = input("Do you accept the license at " + findPackage(packages, "Microsoft.VisualStudio.Product.BuildTools")["localizedResources"][0]["license"] + " (yes/no)? ")
        while response != "yes" and response != "no":
            response = input("Do you accept the license? Answer \"yes\" or \"no\": ")
        if response == "no":
            sys.exit(0)

    setPackageSelection(args, packages)

    if args.list_components or args.list_workloads or args.list_packages:
        if args.list_components:
            listPackageType(packages, "Component")
        if args.list_workloads:
            listPackageType(packages, "Workload")
        if args.list_packages:
            listPackageType(packages, None)
        sys.exit(0)

    if args.print_deps_tree:
        for i in args.package:
            printDepends(packages, i, {}, "", args)
        sys.exit(0)

    if args.print_reverse_deps:
        for i in args.package:
            printReverseDepends(packages, i, "", "", args)
        sys.exit(0)

    selected = getSelectedPackages(packages, args)

    if args.print_selection:
        printPackageList(selected)

    print("Selected %d packages, for a total download size of %s, install size of %s" % (len(selected), formatSize(sumDownloadSize(selected)), formatSize(sumInstalledSize(selected))))

    if args.print_selection:
        sys.exit(0)

    tempcache = None
    if args.cache != None:
        cache = os.path.abspath(args.cache)
    else:
        cache = tempfile.mkdtemp(prefix="vsinstall-")
        tempcache = cache

    if not args.only_download and args.dest == None:
        print("No destination directory set!")
        sys.exit(1)

    try:
        downloadPackages(selected, cache, allowHashMismatch=args.only_download)
        if args.only_download:
            sys.exit(0)

        dest = os.path.abspath(args.dest)

        if args.only_unpack:
            unpack = dest
        else:
            unpack = os.path.join(dest, "unpack")

        extractPackages(selected, cache, unpack)

        if args.with_wdk_installers is not None:
            unpackWin10WDK(args.with_wdk_installers, unpack)

        if sys.platform != "win32":
            # Wine doesn't support dependentAssembly yet.
            # Manually copy dependencies to app directory.
            copyDependentAssemblies(os.path.join(unpack, "MSBuild", "Current", "Bin", "amd64", "MSBuild.exe"))
            copyDependentAssemblies(os.path.join(unpack, "MSBuild", "Current", "Bin", "arm64", "MSBuild.exe"))

        if not args.only_unpack:
            moveVCSDK(unpack, dest)
            if not args.keep_unpack:
                shutil.rmtree(unpack)
            if not args.skip_patch and args.major == 17: # Only apply patches to latest VS
                patchPackages(dest)
    finally:
        if tempcache != None:
            shutil.rmtree(tempcache)
