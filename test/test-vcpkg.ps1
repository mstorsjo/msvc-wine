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

# Create a test port to verify the VS environment.
New-Item test-vcvars -ItemType Directory -Force | Out-Null
Push-Location test-vcvars

@"
{
  "name": "test-vcvars",
  "version": "0"
}
"@ | Out-File vcpkg.json -Encoding utf8

@"
set(VCPKG_POLICY_EMPTY_PACKAGE enabled)

cmake_path(GET GIT PARENT_PATH GIT_PATH)
vcpkg_add_to_path(`${GIT_PATH})

execute_process(
  COMMAND $PWSH [[$PSScriptRoot/test-vcvars.ps1]] -Setup Skip -Root [[$Root]] -HostArch $HostArch -Arch $Arch
  COMMAND_ECHO NONE
  COMMAND_ERROR_IS_FATAL ANY
)
"@ | Out-File portfile.cmake -Encoding utf8

Pop-Location

# Set the environment variables to instruct vcpkg to select desired VS instance.
$env:VS170COMNTOOLS = [IO.Path]::Combine($Root, 'Common7', 'Tools')
$env:VCPKG_VISUAL_STUDIO_PATH = $Root

EXEC "" vcpkg install test-vcvars:$Arch-windows `
              --binarysource=clear `
              --overlay-ports=. `
              --x-buildtrees-root=buildtrees `
              --x-packages-root=packages `
              --x-install-root=installed

QUIT
