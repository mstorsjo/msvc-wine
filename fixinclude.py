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
from pathlib import Path

mapping = {}

def dodir(dir):
    dir = Path(dir)
    for i in dir.listdir():
        path = dir / i
        if i == "." or i == ".." or path.islink():
            continue

        
        if path.isdir():
            dodir(path)
        else:
            with path.open("r") as f:
                lines = f.readlines()

            with open(path + ".out", "w") as f:
                for line in lines:
                    if line.startswith("#include"):
                        values = line.split("//")
                        values[0] = values[0].lower()

                        for from_, to in mapping.items():
                            values[0] = values[0].replace(from_, to)

                        line = "//".join(values)

                    f.write(line)

            path.unlink()
            os.rename(path + ".out", path)


def main(defines):
    global mapping
    for i in range(len(defines)):
        arg = defines[i]
        if arg.startswith("-D"):
            mapping[arg[2:]] = defines[i+1]

    for path in defines[1:]:
        dodir(path)


if __name__ == "__main__":
    import sys

    main(sys.argv)
