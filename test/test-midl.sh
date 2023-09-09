#!/bin/bash
#
# Copyright (c) 2023 Martin Storsjo
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

. "${0%/*}/test.sh"


cat >test-idl.idl <<EOF
import "unknwn.idl";

[
    uuid(73ad110f-de60-4d7a-899a-58f2afc033a7),
]
interface ITestClass : IUnknown
{
    HRESULT DoSomething([in] ULONG param);
}

cpp_quote("DEFINE_GUID(CLSID_TestClassImplementation, 0x5247bb7c,0x51d6,0x42ce,0xa3,0xd1,0x1c,0xe9,0x65,0xf6,0x93,0x72);")
EOF

cat >test-idl.c <<EOF
#include <windows.h>
#include <initguid.h>
#define COBJMACROS
#define INITGUID
#include "test-idl.h"

int main(int argc, char *argv[]) {
    if (argc <= 1)
        return 0;

    ITestClass *obj;
    CoInitializeEx(NULL, COINIT_MULTITHREADED);
    if (CoCreateInstance(&CLSID_TestClassImplementation, 0, CLSCTX_INPROC, &IID_ITestClass, (void*)&obj))
        return 0;
    ITestClass_DoSomething(obj, 0);
    ITestClass_Release(obj);
    return 0;
}
EOF

EXEC "" ${BIN}midl test-idl.idl
EXEC "" ${BIN}cl test-idl.c test-idl_i.c ole32.lib

EXIT
