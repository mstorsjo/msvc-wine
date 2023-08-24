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
import os
import sys

from os import path

do_symlink = False
map_files = False
map_paths = False
mapping = {}

def do_rename(src, destdir, destname):
    dest = path.join(destdir, destname)
    if do_symlink:
        try:
            os.symlink(path.relpath(src, destdir), dest)
        except OSError:
            pass
    else:
        try:
            os.rename(src, dest)
        except OSError as e:
            print(f"Rename: {e}")

def remapName(path):
    name = path.rstrip("/")
    name = name.split("/")[-1]
    name = name.lower()
    if map_paths:
        if name in mapping:
            return mapping[name]
    elif map_files:
        if name in mapping:
            return mapping[name]
    return name

def mergedir(src, dest):
    try:
        dir = os.listdir(src)
    except OSError as e:
        print(f"{src}: {e}")
        return False

    for i in dir:
        if i == "." or i == "..":
            continue
        if path.isdir(path.join(src, i)):
            if path.exists(path.join(dest, i)):
                mergedir(path.join(src, i), path.join(dest, i))
            else:
                do_rename(path.join(src, i), dest, i)
        else:
            do_rename(path.join(src, i), dest, i)

    try:
        os.rmdir(src)
    except OSError:
        pass

    return True

def dodir(dir, relpath):
    try:
        dir_list = os.listdir(dir)
    except OSError as e:
        print(f"{dir}: {e}")
        return False

    for i in dir_list:
        if i == "." or i == "..":
            continue
        relname = relpath + i
        if path.isdir(path.join(dir, i)):
            dodir(path.join(dir, i), relname + "/")
        else:
            new = remapName(relname)
            if i != new:
                do_rename(path.join(dir, i), dir, new)

    dirs = dir.split("/")
    ldir = dirs[-1]
    newname = remapName(relpath)
    newname = ldir.lower() if relpath == "" else newname
    if ldir != newname:
        ndir = path.join("/".join(dirs[:-1]), newname)
        if path.isdir(ndir):
            mergedir(dir, ndir)
        else:
            do_rename(dir, "/".join(dirs[:-1]), newname)

def main(paths, defines, symlink: bool = False, map_winsdk: bool = False):
    global mapping, do_symlink, map_paths, map_files
    if symlink:
        do_symlink = True
    if map_winsdk:
        map_paths = True
        mapping["gl"] = "GL"

    for i in range(len(defines)):
        arg = defines[i]
        if arg == "-map_paths":
            if i + 1 < len(defines):
                with open(defines[i+1], "r") as f:
                    for line in f:
                        line = line.strip()
                        name = line.split("/")[-1]
                        if name.lower() not in mapping:
                            mapping[name.lower()] = line
            map_paths = True
            i += 1
        elif arg == "-map_files":
            if i + 1 < len(defines):
                with open(defines[i+1], "r") as f:
                    for line in f:
                        line = line.strip()
                        name = line.split("/")[-1]
                        if name.lower() not in mapping:
                            mapping[name.lower()] = line
            map_files = True
            i += 1
        else:
            paths = [arg]

    if len(paths) != 1:
        print("Usage: lowercase dir")
        sys.exit(1)

    dodir(paths[0], "")