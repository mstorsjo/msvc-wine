#!/usr/bin/env bash
#
# Copyright (c) 2025 Huang Qinjin
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

vsdownload=$(realpath "${TESTS}../vsdownload.py")
EXEC SaveManifest "$vsdownload" --save-manifest --print-version

manifest=""
manifest_re='Saved installer manifest to "([^"]*)"'
while IFS= read -r line; do
    echo "$line"
    if [[ $line =~ $manifest_re ]]; then
        manifest="${BASH_REMATCH[1]}"
    fi
done < SaveManifest.out
EXEC "" test -f "$manifest"

verify_selection=(
    "$vsdownload"
    --verify-selection -
    --accept-license
    --manifest "$manifest"
)

MSVC="
Microsoft.VisualStudio.Component.VC.Tools.x86.x64 =1
"
ASAN="
Microsoft.VisualCpp.ASAN.X86 =1
"
WINSDK="
Win\d\dSDK_[\d.]+ =1
"
ATL="
Microsoft.VisualStudio.Component.VC.ATL =1
"
DIASDK="
Microsoft.VisualCpp.DIA.SDK =1
"
MSBUILD="
Microsoft.Build =1
Microsoft.Build.Dependencies =1
"
DEVCMD="
Microsoft.VisualStudio.VC.vcvars =1
Microsoft.VisualStudio.PackageGroup.VsDevCmd =1
"
MSVC16="
Microsoft.VisualStudio.Component.VC.VERSION.x86.x64
Microsoft.VC.VERSION.ASAN.X86
Microsoft.VisualStudio.Component.VC.VERSION.ATL
"
GIT="Microsoft.VisualStudio.Component.Git"

EXEC DefaultPackages "${verify_selection[@]}" <<EOF
${MSVC}
${ASAN}
${WINSDK}
${ATL}
${DIASDK}
${MSBUILD}
${DEVCMD}
EOF

EXEC SpecificPackage "${verify_selection[@]}" ${GIT} <<EOF
${GIT}
${MSVC//=1/=0}
${ASAN//=1/=0}
${WINSDK//=1/=0}
${ATL//=1/=0}
${DIASDK//=1/=0}
${MSBUILD//=1/=0}
${DEVCMD//=1/=0}
EOF

EXEC MsvcVersion "${verify_selection[@]}" --msvc-version 17.13 <<EOF
${MSVC16//VERSION/14.43.17.13}
Win11SDK_10.0.22621
${MSVC//=1/=0}
${ASAN//=1/=0}
${WINSDK}
${ATL//=1/=0}
${DIASDK}
${MSBUILD//=1/=0}
EOF

EXEC MsvcVersion+SpecificPackage "${verify_selection[@]}" --msvc-version 17.13 ${GIT} <<EOF
${MSVC16//VERSION/14.43.17.13}
Win11SDK_10.0.22621
${GIT}
${MSVC//=1/=0}
${ASAN//=1/=0}
${WINSDK}
${ATL//=1/=0}
${DIASDK}
${MSBUILD//=1/=0}
EOF

EXEC MsvcVersion+SdkVersion "${verify_selection[@]}" --msvc-version 17.13 --sdk-version 10.0.26100 <<EOF
${MSVC16//VERSION/14.43.17.13}
Win11SDK_10.0.26100
${MSVC//=1/=0}
${ASAN//=1/=0}
${WINSDK}
${ATL//=1/=0}
${DIASDK}
${MSBUILD//=1/=0}
EOF

EXEC SdkVersion "${verify_selection[@]}" --sdk-version 10.0.22621 <<EOF
Win11SDK_10.0.22621
${MSVC}
${ASAN}
${WINSDK}
${ATL}
${DIASDK}
${MSBUILD}
${DEVCMD}
EOF

EXEC SdkVersion+SpecificPackage "${verify_selection[@]}" --sdk-version 10.0.22621 ${GIT} <<EOF
Win11SDK_10.0.22621
${GIT}
${MSVC//=1/=0}
${ASAN//=1/=0}
${WINSDK}
${ATL//=1/=0}
${DIASDK//=1/=0}
${MSBUILD//=1/=0}
${DEVCMD//=1/=0}
EOF

EXEC MsvcVersion+SdkVersion+SpecificPackage "${verify_selection[@]}" --msvc-version 17.13 --sdk-version 10.0.26100 ${GIT} <<EOF
${MSVC16//VERSION/14.43.17.13}
Win11SDK_10.0.26100
${GIT}
${MSVC//=1/=0}
${ASAN//=1/=0}
${WINSDK}
${ATL//=1/=0}
${DIASDK}
${MSBUILD//=1/=0}
EOF

EXEC IgnorePackage "${verify_selection[@]}" ${GIT} --ignore ${GIT} <<EOF
\S+ =0
EOF

EXEC NoSuchPackage "${verify_selection[@]}" no.such.package <<EOF
\S+ =0
EOF

EXIT
