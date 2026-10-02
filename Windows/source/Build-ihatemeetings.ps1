[CmdletBinding()]
param(
    [switch]$Clean,
    [ValidateSet('Auto','MinGW','MSVC')]
    [string]$Toolchain = 'Auto'
)

$ErrorActionPreference = 'Stop'
$src = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $src
$out = Join-Path $root 'ihatemeetings.exe'
$resObj = Join-Path $src 'app.res'

function Find-Command([string]$Name) {
    $c = Get-Command $Name -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    return $null
}
function Invoke-Checked([string]$Exe, [string[]]$Args) {
    Write-Host ('> ' + $Exe + ' ' + ($Args -join ' '))
    & $Exe @Args
    if ($LASTEXITCODE -ne 0) { throw "$Exe failed with exit code $LASTEXITCODE" }
}
if ($Clean) { Remove-Item $out,$resObj -Force -ErrorAction SilentlyContinue }

$mingwGpp = Find-Command 'g++'; $mingwWindres = Find-Command 'windres'
if ($mingwGpp -and $mingwWindres) {
    try { $dump = & $mingwGpp -dumpmachine 2>$null; if ($LASTEXITCODE -ne 0 -or $dump -notmatch 'mingw|windows') { $mingwGpp=$null; $mingwWindres=$null } }
    catch { $mingwGpp=$null; $mingwWindres=$null }
}
if (-not $mingwGpp) { $mingwGpp=Find-Command 'x86_64-w64-mingw32-g++'; $mingwWindres=Find-Command 'x86_64-w64-mingw32-windres' }
$useMinGW = $Toolchain -eq 'MinGW' -or ($Toolchain -eq 'Auto' -and $mingwGpp -and $mingwWindres)
if ($useMinGW) {
    if (-not $mingwGpp -or -not $mingwWindres) { throw 'MinGW-w64 was requested but g++/windres were not found.' }
    Push-Location $src
    try {
        Invoke-Checked $mingwWindres @('-I','.', 'app.rc','-O','coff','-o',$resObj)
        Invoke-Checked $mingwGpp @('-std=c++17','-O2','-Wall','-Wextra','-Wpedantic','-Werror','-static','-static-libgcc','-static-libstdc++','-municode','-mwindows','advanced_main.cpp',$resObj,'-o',$out,'-liphlpapi','-lsetupapi','-lcfgmgr32','-lfwpuclnt','-lrpcrt4','-lcomctl32','-lcomdlg32','-lshell32','-lole32','-luuid','-lws2_32','-lwinmm')
    } finally { Pop-Location }
} else {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path $vswhere)) { throw 'No usable Windows C++ compiler was found. Install Visual Studio C++ Build Tools or MinGW-w64.' }
    $vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not $vs) { throw 'Visual Studio C++ Build Tools are not installed.' }
    $devCmd = Join-Path $vs 'Common7\Tools\VsDevCmd.bat'; $tmp = Join-Path $env:TEMP ('ihatemeetings-build-' + [guid]::NewGuid().ToString('N') + '.cmd')
    $libs = 'iphlpapi.lib setupapi.lib cfgmgr32.lib fwpuclnt.lib rpcrt4.lib comctl32.lib comdlg32.lib shell32.lib ole32.lib uuid.lib ws2_32.lib winmm.lib'
    @"
@echo off
call "$devCmd" -arch=x64 -host_arch=x64 >nul || exit /b 1
cd /d "$src"
rc /nologo /fo app.res app.rc || exit /b 1
cl /nologo /std:c++17 /O2 /W4 /WX /EHsc /MT advanced_main.cpp app.res /Fe:"$out" /link /SUBSYSTEM:WINDOWS /ENTRY:wWinMainCRTStartup $libs || exit /b 1
"@ | Set-Content -LiteralPath $tmp -Encoding ASCII
    try { & cmd.exe /d /c $tmp; if ($LASTEXITCODE -ne 0) { throw "MSVC build failed with exit code $LASTEXITCODE" } }
    finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
}
if (-not (Test-Path $out)) { throw 'Build reported success but ihatemeetings.exe was not produced.' }
Write-Host ''; Write-Host 'SUCCESS'; Write-Host "Output: $out"; Write-Host "SHA256: $((Get-FileHash -Algorithm SHA256 -LiteralPath $out).Hash)"
