#
# Copyright (c) 2024 Huang Qinjin
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

. $PSScriptRoot/test.ps1 @args

function realpath($p) {
    $item = Get-Item -LiteralPath $p
    $target = $item.Target
    $p = if ($target) { "$target" } else { $item.FullName }
    return $p.TrimEnd('\/')
}

# Verify that the compiler uses header files under the installation root.
function VerifyIncludes($file) {
    Select-String 'Note: including file:(.*)' -Path $file |
    ForEach-Object { $_.Matches[0].Groups[1].Value.Trim() } |
    Sort-Object -Unique |
    Where-Object { -not (realpath $_).StartsWith((realpath $Root)) } |
    Out-File cl-showIncludes.bad -Encoding utf8
    DIFF cl-showIncludes.bad -
}

$Platform = switch ($Arch) {
    'x86' { 'Win32' }
    default { $Arch }
}

$MSBuildArch = switch ($HostArch) {
    'x86' { '' }
    'x64' { 'amd64' }
    default { $HostArch }
}

$MSBuild = [IO.Path]::Combine($Root, 'MSBuild', 'Current', 'Bin', $MSBuildArch, 'MSBuild.exe')

$env:CL="/showIncludes"

EXEC "" $MSBuild /v:q /consoleLoggerParameters:ShowCommandLine `
    /fileLogger /fileLoggerParameters:Verbosity=minimal `
    /p:Platform=$Platform /p:Configuration=Release `
    /p:IntDir="${CWD}" /p:OutDir="${CWD}" `
    /p:VcpkgEnabled=false `
    "${TESTS}HelloWorld.vcxproj"

VerifyIncludes msbuild.log

# CMake 3.23 and later supports portable VS instances, which are not known to the Visual Studio Installer.
# CMake 3.31 or later is required if Visual Studio Installer is not installed on the system.
EXEC "" cmake -DCMAKE_GENERATOR_INSTANCE="$Root,version=17.0.0.0" `
    -G "Visual Studio 17 2022" -A "$Platform,version=10.0" `
    -S "$TESTS" -B a

EXEC "" cmake --build a --config RelWithDebInfo '--' `
    /v:q /consoleLoggerParameters:ShowCommandLine `
    /fileLogger /fileLoggerParameters:Verbosity=minimal `
    /p:VcpkgEnabled=false

VerifyIncludes a/msbuild.log

QUIT
