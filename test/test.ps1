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
    [ValidateScript({Test-Path -LiteralPath $_ -PathType Container})]
    $Root = 'C:\msvc',

    [ValidateSet('x86', 'x64', 'amd64', 'arm64')]
    $HostArch = $env:PROCESSOR_ARCHITECTURE.ToLower(),

    [ValidateSet('x86', 'x64', 'amd64', 'arm', 'arm64')]
    $Arch
)

$Root = (Resolve-Path $Root).Path

if ($HostArch -eq 'amd64') {
    $HostArch = 'x64'
}

if ($Arch -eq 'amd64') {
    $Arch = 'x64'
}

if ($MyInvocation.InvocationName -eq '.') {
    $sourced = $true
    $NAME = Split-Path -Leaf $MyInvocation.PSCommandPath
} else {
    $sourced = $false
    $NAME = Split-Path -Leaf $PSCommandPath
}
$TESTS = "$PSScriptRoot$([IO.Path]::DirectorySeparatorChar)"

$num_of_tests = 0
$num_of_fails = 0

if ($PSVersionTable.PSEdition -eq 'Core') {
    $PWSH = @('pwsh', '-ExecutionPolicy', 'Bypass', '-File')
} else {
    $PWSH = @('powershell', '-ExecutionPolicy', 'Bypass', '-File')
}

# Use UTF-8 without BOM for console input/output.
$OutputEncoding = [System.Text.UTF8Encoding]::new()
$ConsoleOutputEncoding = [Console]::OutputEncoding
$ConsoleInputEncoding = [Console]::InputEncoding
[Console]::OutputEncoding = $OutputEncoding
[Console]::InputEncoding = $OutputEncoding
Register-EngineEvent PowerShell.Exiting -SupportEvent -Action {
    [Console]::OutputEncoding = $ConsoleOutputEncoding
    [Console]::InputEncoding = $ConsoleInputEncoding
}

function EXEC {
    param (
        $output,
        $command
    )

    $global:LASTEXITCODE = 1

    if ($output) {
        $stdout = "$output.out"
        $stderr = "$output.err"
        (& $command @args | Out-File $stdout -Encoding utf8) 2>&1 |
            ForEach-Object { $_.Exception.Message } |
            Out-File $stderr -Encoding utf8
    } else {
        Write-Host "EXEC: $command $args"
        & $command @args
    }

    $global:num_of_tests++
    if ($global:LASTEXITCODE -ne 0) {
        $global:num_of_fails++
        if ($output) {
            Write-Host "EXEC: $command $args"
            Get-Content $stdout -Encoding utf8
            Get-Content $stderr -Encoding utf8
            Remove-Item $stdout, $stderr
        }
    }
}

Remove-Item Alias:DIFF -Force

function DIFF {
    $global:LASTEXITCODE = 1
    $input | git --no-pager diff --no-index -R @args 
    $global:num_of_tests++
    if ($global:LASTEXITCODE -ne 0) {
        $global:num_of_fails++
    }
}

function QUIT {
    if ($sourced) {
        Set-Location $TESTS
        Remove-Item -Recurse -Force $CWD
    }

    "EXIT: {0,-16}  total tests: {1,-3}  failed tests: {2,-3}" -f $NAME, $num_of_tests, $num_of_fails | Write-Host -NoNewline
    if ($num_of_fails -gt 0) {
        " ............. Failed" | Write-Host
        exit 1
    } else {
        " ............. Passed" | Write-Host
        exit 0
    }
}

if ($sourced) {
    $CWD = New-Item -ItemType Directory -Path (Join-Path ([IO.Path]::GetTempPath()) ("msvc-wine.tmp." + [IO.Path]::GetRandomFileName()))
    if (-not $CWD) {
        exit 1
    } else {
        $CWD = "$CWD$([IO.Path]::DirectorySeparatorChar)"
        Set-Location $CWD
        return
    }
} else {
    $CWD = $TESTS
    Set-Location $CWD
}

if ($Arch) {
    $TargetArchs = @($Arch)
} else {
    # Windows SDK 10.0.26100.0 no long targets Arm32.
    # Exclude 'arm' for simplicity.
    $TargetArchs = @('x86', 'x64', 'arm64')
}

foreach ($target in $TargetArchs) {
    $vcvars = if ($HostArch -eq $target) {
        switch ($target) {
            'x86' { "vcvars32.bat" }
            'x64' { "vcvars64.bat" }
            default { "vcvars${target}.bat" }
        }
    } else {
        $vcvars_host = if ($HostArch -eq 'x64') { 'amd64' } else { $HostArch }
        $vcvars_target = if ($target -eq 'x64') { 'amd64' } else { $target }
        "vcvars${vcvars_host}_${vcvars_target}.bat"
    }

    $vcvars = [IO.Path]::Combine($Root, 'VC', 'Auxiliary', 'Build', $vcvars)
    if (-not (Test-Path $vcvars)) {
        continue
    }

    $CommonArgs = @('-Root', $Root, '-HostArch', $HostArch, '-Arch', $target)

    EXEC "" @PWSH test-vcvars.ps1 @CommonArgs

    # Github runners define VCPKG_INSTALLATION_ROOT.
    if (-not $env:VCPKG_ROOT -and $env:VCPKG_INSTALLATION_ROOT) {
        $env:VCPKG_ROOT = $env:VCPKG_INSTALLATION_ROOT
    }
    if ($env:VCPKG_ROOT) {
        EXEC "" @PWSH test-vcpkg.ps1 @CommonArgs
    }
}

QUIT
