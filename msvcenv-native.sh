#!/bin/sh
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

#####
# This is a script for setting up env variables for letting native tools
# find headers and libraries installed by the other msvc-wine scripts.
#
# To use this script, execute it like this:
#     BIN=<path-to-msvc-wine-install>/bin/x64 . ./msvcenv-native.sh
# (Note the "." between the BIN variable and the msvcenv-native.sh script.)
# After executing this, you should be able to run clang-cl and lld-link
# without needing to configure paths manually anywhere.
# (If linking by invoking clang or clang-cl, instead of directly calling
# lld-link, it's recommended to use -fuse-ld=lld.)

if [ -z "$BIN" ]; then
    echo Set BIN to point to the directory before launching
else
    ENV="$BIN/msvcenv.sh"
    if [ ! -f "$ENV" ]; then
        echo $ENV doesn\'t exist
    else
        export INCLUDE="$(bash -c ". $ENV && /bin/echo \"\$INCLUDE\"" | sed s/z://g | sed 's/\\/\//g')"
        export LIB="$(bash -c ". $ENV && /bin/echo \"\$LIB\"" | sed s/z://g | sed 's/\\/\//g')"
    fi
fi
