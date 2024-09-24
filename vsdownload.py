#!/usr/bin/python3
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
import concurrent.futures
import functools
import glob
import hashlib
import os
import json
import platform
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request
import zipfile

COLORS = {
    "black": "30",
    "red": "31",
    "green": "32",
    "yellow": "33",
    "blue": "34",
    "magenta": "35",
    "cyan": "36",
    "white": "37",
}

ATTR_CODES = {
    "bold": "1",
    "dim": "2",
    "underline": "4",
    "blink": "5",
    "reverse": "7",
    "hidden": "8",
    "bright": "1",
}

def color_text(text, color=None, attrs=None):
    color_code = COLORS.get(color, "")
    attr_code = ""
    if attrs:
        attr_code = ";".join([ATTR_CODES.get(attr, "") for attr in attrs if attr in ATTR_CODES])
    code = ";".join(filter(None, [attr_code, color_code]))
    if code:
        return f"\033[{code}m{text}\033[0m"
    else:
        return text

def getArgsParser():
    parser = argparse.ArgumentParser(description = "Download and install Visual Studio")
    parser.add_argument("--manifest", metavar="manifest", help="A predownloaded manifest file")
    parser.add_argument("--save-manifest", const=True, action="store_const", help="Store the downloaded manifest to a file")
    parser.add_argument("--major", default=17, metavar="version", help="The major version to download (defaults to 17)")
    parser.add_argument("--preview", dest="type", default="release", const="pre", action="store_const", help="Download the preview version instead of the release version")
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
    parser.add_argument("--architecture", metavar="arch", help="Target architecture to include (x86, x64, arm, arm64)", nargs="*")
    parser.add_argument("--skip-atl", const=True, action="store_const", help="Skip installing the ATL headers")
    parser.add_argument("--skip-diasdk", const=True, action="store_const", help="Skip installing the DIA SDK")
    parser.add_argument("--with-wdk-installers", metavar="dir", help="Install Windows Driver Kit using the provided MSI installers")
    parser.add_argument("--host-arch", metavar="arch", choices=["x86", "x64", "arm64"], help="Specify the host architecture of packages to install")
    return parser

def setPackageSelectionMSVC16(args, packages, userversion, sdk, toolversion, defaultPackages):
    if findPackage(packages, "Microsoft.VisualStudio.Component.VC." + toolversion + ".x86.x64", {}, warn=False):
        if sdk.startswith("10.0.") and int(sdk[5:]) >= 22000:
            sdkpkg = "Win11SDK_" + sdk
        else:
            sdkpkg = "Win10SDK_" + sdk
        args.package.extend([sdkpkg, "Microsoft.VisualStudio.Component.VC." + toolversion + ".x86.x64"])
        if not args.skip_atl:
            args.package.extend(["Microsoft.VisualStudio.Component.VC." + toolversion + ".ATL"])
        for arch in args.extraarchs:
            args.package.extend(["Microsoft.VisualStudio.Component.VC." + toolversion + "." + arch])
            if not args.skip_atl:
                args.package.extend(["Microsoft.VisualStudio.Component.VC." + toolversion + ".ATL." + arch])
    else:
        # Options for toolchains for specific versions. The latest version in
        # each manifest isn't available as a pinned version though, so if that
        # version is requested, try the default version.
        print("Didn't find exact version packages for " + color_text(userversion, "yellow") + ", assuming this is provided by the default/latest version")
        args.package.extend(defaultPackages)

def setPackageSelectionMSVC15(args, packages, userversion, sdk, toolversion, defaultPackages):
    if findPackage(packages, "Microsoft.VisualStudio.Component.VC.Tools." + toolversion, {}, warn=False):
        args.package.extend(["Win10SDK_" + sdk, "Microsoft.VisualStudio.Component.VC.Tools." + toolversion])
    else:
        # Options for toolchains for specific versions. The latest version in
        # each manifest isn't available as a pinned version though, so if that
        # version is requested, try the default version.
        print("Didn't find exact version packages for " + color_text(userversion, "yellow") + ", assuming this is provided by the default/latest version")
        args.package.extend(defaultPackages)

def setPackageSelection(args, packages):
    if not args.architecture:
        args.architecture = ["x86", "x64", "arm", "arm64"]
    extraarchs = []
    if "arm" in args.architecture:
        extraarchs.extend(["ARM"])
    if "arm64" in args.architecture:
        extraarchs.extend(["ARM64"])
    args.extraarchs = extraarchs

    # If no packages are selected, install these versionless packages, which
    # gives the latest/recommended version for the current manifest.
    defaultPackages = ["Microsoft.VisualStudio.Workload.VCTools"]
    if not args.skip_atl:
        defaultPackages.extend(["Microsoft.VisualStudio.Component.VC.ATL"])
    for arch in extraarchs:
        defaultPackages.extend(["Microsoft.VisualStudio.Component.VC.Tools." + arch])
        if not args.skip_atl:
            defaultPackages.extend(["Microsoft.VisualStudio.Component.VC.ATL." + arch])

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
        print(color_text(f"Unsupported MSVC toolchain version {args.msvc_version}", "red"))
        sys.exit(1)

    if len(args.package) == 0:
        args.package = defaultPackages

    if args.sdk_version != None:
        for key in packages:
            if key.startswith("win10sdk") or key.startswith("win11sdk"):
                base = key[0:8]
                sdkname = base + "_" + args.sdk_version
                if key == sdkname:
                    args.package.append(key)
                else:
                    args.ignore.append(key)
        p = packages[key][0]

def lowercaseIgnores(args):
    ignore = []
    if args.ignore != None:
        for i in args.ignore:
            ignore.append(i.lower())
    args.ignore = ignore

def getManifest(args):
    if args.manifest == None:
        url = "https://aka.ms/vs/%s/%s/channel" % (args.major, args.type)
        print("Fetching %s" % (color_text(url, "cyan")))
        manifest = json.loads(urllib.request.urlopen(url).read())
        version = manifest["info"]["productDisplayVersion"]
        print("Got toplevel manifest for %s" % (color_text(version, "yellow", ["bold"])))
        for item in manifest["channelItems"]:
            if "type" in item and item["type"] == "Manifest":
                args.manifest = item["payloads"][0]["url"]
        if args.manifest == None:
            print(color_text("Unable to find an installer manifest!", "red", ["bold"]))
            sys.exit(1)

    if not args.manifest.startswith("http"):
        args.manifest = "file:" + args.manifest

    manifestdata = urllib.request.urlopen(args.manifest).read()
    manifest = json.loads(manifestdata)
    version = manifest["info"]["productDisplayVersion"]
    print("Loaded installer manifest for %s" % (color_text(version, "yellow", ["bold"])))

    if args.save_manifest:
        filename = "%s.manifest" % (version)
        if os.path.isfile(filename):
            oldfile = open(filename, "rb").read()
            if oldfile != manifestdata:
                print("Old saved manifest in \"%s\" differs from newly downloaded one, not overwriting!" % (color_text(filename, "yellow")))
            else:
                print("Old saved manifest in \"%s\" is still current" % (color_text(filename, "green")))
        else:
            f = open(filename, "wb")
            f.write(manifestdata)
            f.close()
            print("Saved installer manifest to \"%s\"" % (color_text(filename, "green")))

    return manifest

def prioritizePackage(arch, a, b):
    def archOrd(k, x):
        if arch is None:
            return 0
        c = x.get(k)
        if c is None:
            return 0
        c = c.lower()
        if c == "neutral":
            return -1
        if c == arch:
            return -2
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
        print(color_text(id, "cyan"))

def findPackage(packages, id, constraints, warn=True):
    origid = id
    id = id.lower()
    candidates = None
    if not id in packages:
        if warn:
            print(color_text("WARNING: %s not found" % (origid), "yellow"))
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

def printDepends(packages, target, constraints, prefix, is_last, args):
    chipstr = ""
    for k in ["chip", "machineArch"]:
        v = constraints.get(k)
        if v is not None:
            chipstr += f" ({k}.{v})"
    deptypestr = ""
    deptype = constraints.get("type", "")
    if deptype != "":
        deptypestr = f" ({deptype})"
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
        p = findPackage(packages, target, constraints, False)
        if p == None:
            ignorestr = " (NotFound)"
            ignore = True

    connector = "└── " if is_last else "├── "
    colored_connector = color_text(connector, "white", ["bright"])
    line = target + chipstr + deptypestr + ignorestr
    line_color = "green" if not ignore else "red"
    print(prefix + colored_connector + color_text(line, line_color))
    if ignore:
        return
    new_prefix = prefix + ("    " if is_last else "│   ")
    dependencies = list(p.get("dependencies", {}).items())
    for idx, (dep_target, dep_constraints) in enumerate(dependencies):
        if not isinstance(dep_constraints, dict):
            dep_constraints = { "version": dep_constraints }
        is_last_dep = idx == len(dependencies) - 1
        printDepends(packages, dep_target, dep_constraints, new_prefix, is_last_dep, args)

def printReverseDepends(packages, target, deptype, prefix, is_last, args):
    deptypestr = ""
    if deptype != "":
        deptypestr = " (" + deptype + ")"
    connector = "└── " if is_last else "├── "
    colored_connector = color_text(connector, "white", ["bright"])
    print(prefix + colored_connector + color_text(target + deptypestr, "cyan"))
    if deptype == "Optional" and not args.include_optional:
        return
    if deptype == "Recommended" and args.skip_recommended:
        return
    target_lower = target.lower()
    dependents = []
    for key in packages:
        p = packages[key][0]
        if "dependencies" in p:
            deps = p["dependencies"]
            for k in deps:
                if k.lower() != target_lower:
                    continue
                dep = deps[k]
                dep_type = ""
                if isinstance(dep, dict):
                    dep_type = dep.get("type", "")
                else:
                    dep_type = ""
                dependents.append((p["id"], dep_type))
    for idx, (dep_id, dep_type) in enumerate(dependents):
        is_last_dep = idx == len(dependents) - 1
        new_prefix = prefix + ("    " if is_last else "│   ")
        printReverseDepends(packages, dep_id, dep_type, new_prefix, is_last_dep, args)

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
    packagekey = getPackageKey(p)
    if packagekey in included:
        return []
    ret = [p]
    included[packagekey] = True
    for target, constraints in p.get("dependencies", {}).items():
        if not isinstance(constraints, dict):
            constraints = { "version": constraints }
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
        package_name = color_text(p["id"], "green")
        s = package_name
        if "type" in p:
            s += " (" + p["type"] + ")"
        for k in ["chip", "machineArch", "productArch"]:
            v = p.get(k)
            if v is not None:
                s += " (" + k + "." + v + ")"
        if "language" in p:
            s += " (" + p["language"] + ")"
        size_str = color_text(formatSize(sumInstalledSize([p])), "yellow")
        s += " " + size_str
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

def downloadPackages(selected, cache, allowHashMismatch=False):
    stop_event = threading.Event()
    makedirs(cache)
    args_list = []
    for p in selected:
        if not "payloads" in p:
            continue
        dir = os.path.join(cache, getPackageKey(p))
        makedirs(dir)
        for payload in p["payloads"]:
            name = getPayloadName(payload)
            destname = os.path.join(dir, name)
            fileid = os.path.join(getPackageKey(p), name)
            args = (payload, destname, fileid, allowHashMismatch, stop_event)
            args_list.append(args)

    downloaded = 0
    start_time = time.time()

    with concurrent.futures.ThreadPoolExecutor(max_workers=os.cpu_count()) as executor:
        futures = [executor.submit(_downloadPayload, *args) for args in args_list]
        try:
            for future in concurrent.futures.as_completed(futures):
                downloaded += future.result()
        except KeyboardInterrupt:
            print(color_text("\nDownload interrupted by user. Stopping!", "red", ["bold"]))
            stop_event.set()
            # Wait for all futures to finish
            for future in futures:
                future.cancel()
            executor.shutdown(wait=False)
            sys.exit(1)
        except Exception as e:
            stop_event.set()
            executor.shutdown(wait=False)
            raise e

    end_time = time.time()
    total_time = end_time - start_time

    hours, rem = divmod(total_time, 3600)
    minutes, seconds = divmod(rem, 60)
    time_str = ""
    if hours > 0:
        time_str += "%d hours " % hours
    if minutes > 0 or hours > 0:
        time_str += "%d minutes " % minutes
    time_str += "%.2f seconds" % seconds

    print("Downloaded %s in total in %s" % (
        color_text(formatSize(downloaded), "yellow", ["bold"]),
        color_text(time_str.strip(), "yellow", ["bold"])
    ))

print_lock = threading.Lock()

def safe_print(*args, **kwargs):
    with print_lock:
        print(*args, **kwargs)

def _downloadPayload(payload, destname, fileid, allowHashMismatch, stop_event):
    attempts = 5
    for attempt in range(attempts):
        if stop_event.is_set():
            return 0
        try:
            if os.access(destname, os.F_OK):
                if "sha256" in payload:
                    if sha256File(destname).lower() != payload["sha256"].lower():
                        message = "%s %s, %s" % (
                            color_text("Incorrect existing file", "yellow"),
                            color_text(fileid, "cyan"),
                            color_text("removing", "red"))
                        safe_print(message)
                        os.remove(destname)
                    else:
                        message = "%s %s" % (
                            color_text("Using existing file", "green"),
                            color_text(fileid, "cyan"))
                        safe_print(message)
                        return 0
                else:
                    return 0
            size = 0
            if "size" in payload:
                size = payload["size"]
            size_str = color_text("(%s)" % formatSize(size), "yellow")
            message = "%s %s %s" % (
                color_text("Downloading", "white", ["bold"]),
                color_text(fileid, "cyan"),
                size_str)
            safe_print(message)

            url = payload["url"]
            req = urllib.request.Request(url)
            with urllib.request.urlopen(req, timeout=10) as response, open(destname, 'wb') as out_file:
                chunk_size = 8192
                while not stop_event.is_set():
                    chunk = response.read(chunk_size)
                    if not chunk:
                        break
                    out_file.write(chunk)
                if stop_event.is_set():
                    # Remove partial file
                    out_file.close()
                    os.remove(destname)
                    return 0
            if "sha256" in payload:
                if sha256File(destname).lower() != payload["sha256"].lower():
                    if allowHashMismatch:
                        safe_print(color_text("WARNING: Incorrect hash for downloaded file %s" % (fileid), "yellow"))
                    else:
                        raise Exception("Incorrect hash for downloaded file %s, aborting" % fileid)
            return size
        except Exception as e:
            if stop_event.is_set() or attempt == attempts - 1:
                raise
            safe_print(color_text("%s: %s" % (type(e).__name__, e), "red"))
    return 0

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
    for payload in payloads:
        name = getPayloadName(payload)
        if name.endswith(".msi"):
            print(
                color_text("Extracting ", "green", ["bold"])
                + color_text(name, "cyan")
            )
            srcfile = os.path.join(src, name)
            if sys.platform == "win32":
                cmd = ["msiexec", "/a", srcfile, "/qn", "TARGETDIR=" + os.path.abspath(dest)]
            else:
                cmd = ["msiextract", "-C", dest, srcfile]
            with open(os.path.join(dest, "WinSDK-" + getPayloadName(payload) + "-listing.txt"), "w") as log:
                subprocess.check_call(cmd, stdout=log)

def unpackWin10WDK(src, dest):
    print("Unpacking WDK installers from " + color_text(src, "cyan"))

    # WDK installers downloaded by wdksetup.exe include a huge pile of
    # non-WDK installers, just skip these.
    for srcfile in glob.glob(src + "/Windows Driver*.msi"):
        name = os.path.basename(srcfile)
        print("Extracting " + color_text(name, "cyan"))

        # Do not try to run msiexec here because TARGETDIR
        # does not work with WDK installers.
        cmd = ["msiextract", "-C", dest, srcfile]

        payloadName, _ = os.path.splitext(name)
        with open(os.path.join(dest, "WDK-" + payloadName + "-listing.txt"), "w") as log:
            subprocess.check_call(cmd, stdout=log)

    # WDK includes a VS extension, unpack it before copying the extracted files.
    for vsix in glob.glob(dest + "/**/WDK.vsix", recursive=True):
        name = os.path.basename(vsix)
        print("Unpacking WDK VS extension " + color_text(name, "cyan"))

        payloadName, _ = os.path.splitext(name)
        listing = os.path.join(dest, "WDK-VS-" + payloadName + "-listing.txt")
        unpackVsix(vsix, dest, listing)

    # Merge incorrectly extracted 'Build' and 'build' directory trees.
    # The WDK 'build' tree must be versioned.
    kitsPath = os.path.join(dest, "Program Files", "Windows Kits", "10")
    brokenBuildDir = os.path.join(kitsPath, "Build")
    for buildDir in glob.glob(kitsPath + "/build/10.*/"):
        wdkVersion = buildDir.split("/")[-2];
        print("Merging WDK 'Build' and 'build' directories into version " + color_text(wdkVersion, "yellow"));
        mergeTrees(brokenBuildDir, buildDir)
    shutil.rmtree(brokenBuildDir)

    # Move the WDK .props files into a versioned directory.
    propsPath = os.path.join(kitsPath, "DesignTime", "CommonConfiguration", "Neutral", "WDK");
    versionedPath = os.path.join(propsPath, wdkVersion)
    makedirs(versionedPath)
    for props in glob.glob(propsPath + "/*.props"):
        filename = os.path.basename(props)
        print("Moving " + color_text(filename, "cyan") + " into version " + color_text(wdkVersion, "yellow"));
        shutil.move(props, os.path.join(versionedPath, filename))

def extractPackages(selected, cache, dest):
    makedirs(dest)
    for p in selected:
        type = p["type"]
        dir = os.path.join(cache, getPackageKey(p))
        if type == "Component" or type == "Workload" or type == "Group":
            continue
        if type == "Vsix":
            print(
                color_text("Unpacking ", "blue", ["bold"])
                + color_text(p["id"], "cyan")
            )
            for payload in p["payloads"]:
                unpackVsix(
                    os.path.join(dir, getPayloadName(payload)),
                    dest,
                    os.path.join(dest, getPackageKey(p) + "-listing.txt"),
                )
        elif p["id"].startswith("Win10SDK") or p["id"].startswith("Win11SDK"):
            print(
                color_text("Unpacking ", "blue", ["bold"])
                + color_text(p["id"], "cyan")
            )
            unpackWin10SDK(dir, p["payloads"], dest)
        else:
            print(
                color_text("Skipping unpacking of ", "yellow", ["bold"])
                + color_text(p["id"], "cyan")
                + color_text(" of type ", "yellow", ["bold"])
                + color_text(type, "magenta")
            )

def moveVCSDK(unpack, dest):
    # Move the VC and Program Files\Windows Kits\10 directories
    # out from the unpack directory, allowing the rest of unpacked
    # files to be removed.
    mergeTrees(os.path.join(unpack, "VC"), os.path.join(dest, "VC"))
    kitsPath = unpack
    # msiexec extracts to Windows Kits rather than Program Files\Windows Kits
    if sys.platform != "win32":
        kitsPath = os.path.join(kitsPath, "Program Files")
    mergeTrees(os.path.join(kitsPath, "Windows Kits"), os.path.join(dest, "Windows Kits"))

    # Move other VC components directories:
    # The DIA SDK isn't necessary for normal use, but can be used when e.g.
    # compiling LLVM.
    # MSBuild is the standard VC build tool.
    dirs = ["MSBuild"]
    if not args.skip_diasdk:
        dirs.extend(["DIA SDK"])
    for extraDir in dirs:
        mergeTrees(os.path.join(unpack, extraDir), os.path.join(dest, extraDir))

if __name__ == "__main__":
    parser = getArgsParser()
    args = parser.parse_args()
    lowercaseIgnores(args)

    socket.setdefaulttimeout(15)

    if args.host_arch is None:
        args.host_arch = platform.machine().lower()
        if platform.system() == "Darwin":
            args.host_arch = "x64"
        elif args.host_arch in [ "x86", "i386", "i686" ]:
            args.host_arch = "x86"
        elif args.host_arch in [ "x64", "x86_64", "amd64" ]:
            args.host_arch = "x64"
        elif args.host_arch in [ "arm64", "aarch64" ]:
            args.host_arch = "arm64"
        else:
            args.host_arch = None

    if args.host_arch is None:
        print(color_text("WARNING: Unable to detect host architecture", "yellow"))
    else:
        print("Install packages for %s host architecture" % color_text(args.host_arch, "yellow", ["bold"]))

    packages = getPackages(getManifest(args), args.host_arch)

    if args.print_version:
        sys.exit(0)

    if not args.accept_license:
        license_url = findPackage(packages, "Microsoft.VisualStudio.Product.BuildTools", {})["localizedResources"][0]["license"]
        response = input("Do you accept the license at " + color_text(license_url, "cyan") + " (yes/no)? ")
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
        for idx, i in enumerate(args.package):
            is_last = idx == len(args.package) - 1
            printDepends(packages, i, {}, "", is_last, args)
        sys.exit(0)

    if args.print_reverse_deps:
        for idx, i in enumerate(args.package):
            is_last = idx == len(args.package) - 1
            printReverseDepends(packages, i, "", "", is_last, args)
        sys.exit(0)

    selected = getSelectedPackages(packages, args)

    if args.print_selection:
        printPackageList(selected)

    packages_count = color_text(str(len(selected)), "green")
    total_download_size = color_text(formatSize(sumDownloadSize(selected)), "yellow")
    total_install_size = color_text(formatSize(sumInstalledSize(selected)), "yellow")
    print("Selected %s packages, for a total download size of %s, install size of %s" % (packages_count, total_download_size, total_install_size))

    if args.print_selection:
        sys.exit(0)

    tempcache = None
    if args.cache != None:
        cache = os.path.abspath(args.cache)
    else:
        cache = tempfile.mkdtemp(prefix="vsinstall-")
        tempcache = cache

    if not args.only_download and args.dest == None:
        print(color_text("No destination directory set!", "red", ["bold"]))
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

        if not args.only_unpack:
            moveVCSDK(unpack, dest)
            if not args.keep_unpack:
                shutil.rmtree(unpack)
    finally:
        if tempcache != None:
            shutil.rmtree(tempcache)
