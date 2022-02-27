#!/usr/bin/env python

import sys
from re import sub, escape, M
from shlex import quote

s = sys.stdin.read()
for arg in sys.argv[1:]:
    key, val = arg.split("=", 1)
    s = sub(f"^{escape(key)}=.*", lambda match: f"{key}={quote(val)}", s, flags=M)
sys.stdout.write(s)
