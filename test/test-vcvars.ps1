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

param(
    [ValidateSet('InvokeCmd', 'Skip')]
    $Setup = 'InvokeCmd'
)

. $PSScriptRoot/test.ps1 @args

if ($Setup -eq 'InvokeCmd') {
    $vcvars_bat = [IO.Path]::Combine($Root, 'VC', 'Auxiliary', 'Build', 'vcvarsall.bat')
    $vcvars_arch = if ($HostArch -eq $Arch) { $Arch } else { "${HostArch}_$Arch" }
    $dumpenv = "Get-ChildItem Env: | Select-Object Name,Value | ConvertTo-Json | Out-File env.json -Encoding utf8"
    
    EXEC "" cmd /c """$vcvars_bat"" $vcvars_arch && $($PWSH[0]) -Command ""& { $dumpenv }"""
    # https://stackoverflow.com/questions/63388883
    # Parentheses are needed before powershell 7 to enumerate the array produced by ConvertFrom-Json.
    (Get-Content -LiteralPath env.json -Encoding utf8 | ConvertFrom-Json) | ForEach-Object {
        Set-Item -LiteralPath Env:$($_.Name) -Value $_.Value
    }
}

function which($cmd) {
    $path = (Get-Command $cmd -ErrorAction Ignore).Path
    $name = $cmd.Replace('.', '_')
    Set-Variable $name -Value $path -Scope Script
    return $name
}

function realpath($p) {
    $item = Get-Item -LiteralPath $p
    $target = $item.Target
    $p = if ($target) { "$target" } else { $item.FullName }
    return $p.TrimEnd('\/')
}

function TestRealPath($name, $expected) {
    $value = Get-Variable $name -ValueOnly -ErrorAction Ignore
    if (-not $value) { $value = (Get-Item -LiteralPath Env:$name).Value }
    if ((realpath $value) -eq (realpath $expected)) {
        $global:LASTEXITCODE = 0
    } else {
        $global:LASTEXITCODE = 1
        Write-Host "ERROR: $name=""$value"""
    }
}

$MSBuildArch = switch ($HostArch) {
    'x86' { '' }
    'x64' { 'amd64' }
    default { $HostArch }
}

EXEC "" TestRealPath VSINSTALLDIR         $Root
EXEC "" TestRealPath VCToolsInstallDir    ([IO.Path]::Combine($Root, 'VC', 'Tools', 'MSVC', $env:VCToolsVersion))
EXEC "" TestRealPath WindowsSdkDir        ([IO.Path]::Combine($Root, 'Windows Kits', '10'))
EXEC "" TestRealPath UniversalCRTSdkDir   ([IO.Path]::Combine($Root, 'Windows Kits', '10'))
EXEC "" TestRealPath (which cl.exe     )  ([IO.Path]::Combine($Root, 'VC', 'Tools', 'MSVC', $env:VCToolsVersion, 'bin', "Host$HostArch", $Arch, 'cl.exe'))
EXEC "" TestRealPath (which rc.exe     )  ([IO.Path]::Combine($Root, 'Windows Kits', '10', 'bin', $env:WindowsSDKVersion, $HostArch, 'rc.exe'))
EXEC "" TestRealPath (which MSBuild.exe)  ([IO.Path]::Combine($Root, 'MSBuild', 'Current', 'Bin', $MSBuildArch, 'MSBuild.exe'))

# Verify that the compiler uses header files under the installation root.
EXEC cl-showIncludes cl /showIncludes /P ${TESTS}headers.cpp
if ($global:LASTEXITCODE -eq 0) {
    Select-String 'Note: including file:(.*)' -Path cl-showIncludes.err -Encoding utf8 |
    ForEach-Object { $_.Matches[0].Groups[1].Value.Trim() } |
    Sort-Object -Unique |
    Where-Object { -not (realpath $_).StartsWith((realpath $Root)) } |
    Out-File cl-showIncludes.bad -Encoding utf8
    DIFF cl-showIncludes.bad -
}

QUIT
