<#
.SYNOPSIS
  Build and run NX Open C++ DLL skills (batch NX session, loaded and invoked from PowerShell).

.DESCRIPTION
  setup : check NX install, NX Open (UGOPEN), UGII_* environment variables and MSVC (exit 10 when not ready).
  build : compile <Source.cpp> into <Name>.dll with MSVC (exports NxMain).
  run   : load <Name>.dll into a small precompiled host process (tools\hosts\NxRunHost.cs) and call
          extern "C" int NxMain(int argc, char* argv[]).  argv[0] is the DLL path,
          argv[1..] are the extra arguments.  The script exit code equals the NxMain return value.

  Run each invocation in a fresh process (powershell -File ...) so the DLL is unlocked afterwards.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File NX\tools\nxrun.ps1 build <Task>\Measure.cpp
  powershell -NoProfile -ExecutionPolicy Bypass -File NX\tools\nxrun.ps1 run <Task>\Measure.dll "<model.prt>"
#>
param(
    [Parameter(Mandatory, Position = 0)][ValidateSet('setup', 'build', 'run')][string]$Command,
    [Parameter(Position = 1)][string]$Path,
    [Parameter(Position = 2, ValueFromRemainingArguments)][string[]]$NxArgs
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\tools\memcheck.ps1'); Assert-Memory 'NX'
. (Join-Path $PSScriptRoot '..\..\tools\envdetect.ps1')

if ($Command -eq 'setup') {
    $bad = New-Object System.Collections.Generic.List[string]
    function Ok($m)   { Write-Host "[OK] $m" }
    function Warn($m) { Write-Host "[!]  $m" }
    function Fail($m) { Write-Host "[X]  $m"; $bad.Add($m) }

    # 1. NX installation
    $installs = @(Find-NxInstalls)
    $base = $env:UGII_BASE_DIR
    if (-not $base -and $installs.Count -gt 0) { $base = $installs[-1].Path }
    if ($installs.Count -gt 0) { Ok ('NX installed: ' + (($installs | ForEach-Object { "$($_.Path) (version $($_.Version))" }) -join '; ')) }
    elseif ($base -and (Test-Path (Join-Path $base 'NXBIN'))) { Ok "NX installed: $base" }
    else { Fail 'NX is not installed (no NXBIN folder found). Install Siemens NX first, or set UGII_BASE_DIR to its install folder.' }

    # 2. NX Open (UGOPEN) C++ headers and libraries
    if ($base) {
        $ug = Join-Path $base 'UGOPEN'
        $need = @('NXOpen\Session.hxx', 'uf.h', 'libnxopencpp.lib', 'libufun.lib', 'libnxopencpp_assemblies.lib', 'libnxopencpp_facet.lib')
        $miss = @($need | Where-Object { -not (Test-Path (Join-Path $ug $_)) })
        if ($miss.Count -eq 0) { Ok "NX Open C++ present: $ug" }
        else { Fail "NX Open (UGOPEN) incomplete under $ug, missing: $($miss -join ', '). Reinstall NX with the 'NX Open' / programming option." }
    }

    # 3. Environment variables
    if (-not $env:UGII_BASE_DIR) {
        Fail "UGII_BASE_DIR is not set. Fix (new terminal afterwards): setx UGII_BASE_DIR `"$base`""
    }
    elseif (-not (Test-Path $env:UGII_BASE_DIR)) { Fail "UGII_BASE_DIR points to a missing folder: $env:UGII_BASE_DIR" }
    else { Ok "UGII_BASE_DIR = $env:UGII_BASE_DIR" }

    if (-not $env:UGII_ROOT_DIR) {
        Fail "UGII_ROOT_DIR is not set. Fix (new terminal afterwards): setx UGII_ROOT_DIR `"$base\NXBIN`""
    }
    elseif (-not (Test-Path $env:UGII_ROOT_DIR)) { Fail "UGII_ROOT_DIR points to a missing folder: $env:UGII_ROOT_DIR" }
    else { Ok "UGII_ROOT_DIR = $env:UGII_ROOT_DIR" }

    if ($env:UGII_BASE_DIR -and $env:UGII_ROOT_DIR -and -not $env:UGII_ROOT_DIR.StartsWith($env:UGII_BASE_DIR, [StringComparison]::OrdinalIgnoreCase)) {
        Warn 'UGII_ROOT_DIR is not under UGII_BASE_DIR (different NX versions mixed?).'
    }
    if ($env:UGS_LICENSE_SERVER -or $env:SPLM_LICENSE_SERVER) { Ok 'License server variable is set.' }
    else { Warn 'UGS_LICENSE_SERVER / SPLM_LICENSE_SERVER not set; batch NX needs a reachable license.' }

    # 4. Toolchain
    if (-not [Environment]::Is64BitProcess) { Fail 'PowerShell is 32-bit; use 64-bit PowerShell.' }
    $vc = Find-VcRoot
    if ($vc) { Ok "MSVC x64 toolchain: $vc" } else { Fail 'MSVC C++ x64 toolchain not found. Install Visual Studio Build Tools ''Desktop development with C++''.' }

    if ($bad.Count -gt 0) { Write-Host "SETUP FAILED: $($bad.Count) problem(s)."; exit 10 }
    Write-Host 'SETUP OK'
    exit 0
}

if (-not $Path) { Write-Error "'$Command' requires a path."; exit 2 }

if (-not $env:UGII_BASE_DIR -or -not $env:UGII_ROOT_DIR) {
    Write-Error 'UGII_BASE_DIR / UGII_ROOT_DIR are not set. Run nxrun.ps1 setup.'
    exit 10
}

if ($Command -eq 'build') {
    $src = (Resolve-Path $Path).Path
    $dir = Split-Path $src -Parent
    $name = [IO.Path]::GetFileNameWithoutExtension($src)
    $vcvars = Find-VcVars64
    if (-not $vcvars) { Write-Error 'MSVC (vcvars64.bat) not found.'; exit 3 }

    # Load the MSVC environment into this process and call cl.exe directly (no temp .bat file).
    if (-not (Import-VcEnvironment $vcvars)) { Write-Error 'Could not load the MSVC environment (cl.exe).'; exit 3 }
    $ug = Join-Path $env:UGII_BASE_DIR 'ugopen'
    Push-Location $dir
    try {
        & cl.exe /nologo /EHsc /MD /std:c++17 /LD "/I$ug" $src "/Fe:$name.dll" /link "/LIBPATH:$ug" libnxopencpp.lib libufun.lib libnxopencpp_assemblies.lib libnxopencpp_facet.lib
        $rc = $LASTEXITCODE
    }
    finally { Pop-Location }
    foreach ($ext in 'obj', 'exp', 'lib') { Remove-Item (Join-Path $dir "$name.$ext") -ErrorAction SilentlyContinue }
    if ($rc -ne 0) { Write-Host "BUILD FAILED (exit $rc)"; exit $rc }
    Write-Host "BUILD OK: $(Join-Path $dir "$name.dll")"
    exit 0
}

# ---- run ----
$dll = (Resolve-Path $Path).Path
$env:PATH = "$env:UGII_ROOT_DIR;$env:PATH"

# Precompiled host (tools\hosts\NxRunHost.cs, built with csc on first use) - no inline native-interop code here.
. (Join-Path $PSScriptRoot '..\..\tools\hostbuild.ps1')
try { $hostExe = Get-RunHost 'NxRunHost' } catch { Write-Host $_.Exception.Message; exit 3 }

$hostArgs = @($dll)
if ($NxArgs) { $hostArgs += @($NxArgs) }
& $hostExe @hostArgs
$rc = $LASTEXITCODE
Write-Host "ExitCode=$rc"
exit $rc
