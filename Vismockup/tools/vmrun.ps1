<#
.SYNOPSIS
  Build and run Vismockup COM-automation C# skills (compiled to a DLL, loaded and invoked from PowerShell).

.DESCRIPTION
  setup : check Vismockup COM registration (VFFrame.Application), the C# compiler and 64-bit PowerShell (exit 10 when not ready).
  build : compile <Skill>.cs into <Skill>.dll (.NET Framework 4.x csc, C# 5, x64). Build failure exits 12.
  run   : load <Skill>.dll, then on an STA thread call the single exported
          public static int Run(string[] args). The args are the remaining "key=value" strings.
          The script exit code equals the Run return value (13 when the skill throws).

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File Vismockup\tools\vmrun.ps1 build Vismockup\Task\ListSelectedNodes\ListSelectedNodes.cs
  powershell -NoProfile -ExecutionPolicy Bypass -File Vismockup\tools\vmrun.ps1 run Vismockup\Task\ListSelectedNodes\ListSelectedNodes.dll radians=true
#>
param(
    [Parameter(Mandatory, Position = 0)][ValidateSet('setup', 'build', 'run')][string]$Command,
    [Parameter(Position = 1)][string]$Path,
    [Parameter(Position = 2, ValueFromRemainingArguments)][string[]]$SkillArgs
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\tools\memcheck.ps1'); Assert-Memory 'Vismockup'
$csc = Join-Path $env:windir 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'

if ($Command -eq 'setup') {
    $bad = New-Object System.Collections.Generic.List[string]
    function Ok($m)   { Write-Host "[OK] $m" }
    function Warn($m) { Write-Host "[!]  $m" }
    function Fail($m) { Write-Host "[X]  $m"; $bad.Add($m) }

    # 1. Vismockup COM registration
    $clsid = $null
    $key = 'Registry::HKEY_CLASSES_ROOT\VFFrame.Application\CLSID'
    if (Test-Path $key) { $clsid = (Get-ItemProperty $key).'(default)' }
    if (-not $clsid) {
        Fail "COM ProgID 'VFFrame.Application' is not registered. Install Teamcenter Visualization (Vismockup) and run it once."
    }
    else {
        $exe = $null
        foreach ($k in 'LocalServer32', 'InprocServer32') {
            $p = "Registry::HKEY_CLASSES_ROOT\CLSID\$clsid\$k"
            if (Test-Path $p) { $exe = ((Get-ItemProperty $p).'(default)') -replace '^"|"$|"\s.*$', ''; break }
        }
        if ($exe -and (Test-Path $exe)) { Ok "Vismockup COM server: $exe" }
        else { Fail "VFFrame.Application is registered but the server file is missing: $exe" }
    }

    # 2. Toolchain
    if (-not [Environment]::Is64BitProcess) { Fail 'PowerShell is 32-bit; use 64-bit PowerShell.' }
    if (Test-Path $csc) { Ok "C# compiler: $csc" } else { Fail "csc.exe not found: $csc (install .NET Framework 4.x)." }

    # 3. Running instance (skills attach to it so SelectedNodes is available)
    $proc = Get-Process -Name 'VisView*' -ErrorAction SilentlyContinue
    if ($proc) { Ok "Vismockup ($($proc[0].Name)) is running, pid $($proc[0].Id)." }
    else { Warn 'Vismockup is not running. Ask the user to start it, open the model and select nodes before run.' }

    if ($bad.Count -gt 0) { Write-Host "SETUP FAILED: $($bad.Count) problem(s)."; exit 10 }
    Write-Host 'SETUP OK'
    exit 0
}

if (-not $Path) { Write-Error "'$Command' requires a path."; exit 2 }

if ($Command -eq 'build') {
    if (-not (Test-Path $csc)) { Write-Error "csc.exe not found: $csc"; exit 3 }
    $src = (Resolve-Path $Path).Path
    $dir = Split-Path $src -Parent
    $name = [IO.Path]::GetFileNameWithoutExtension($src)
    $out = Join-Path $dir "$name.dll"
    & $csc /nologo /target:library /platform:x64 /langversion:5 /optimize+ /r:Microsoft.CSharp.dll /r:System.Core.dll "/out:$out" $src
    if ($LASTEXITCODE -ne 0) { Write-Host "BUILD FAILED (exit $LASTEXITCODE)"; exit 12 }
    Write-Host "BUILD OK: $out"
    exit 0
}

# ---- run ----
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$dll = (Resolve-Path $Path).Path
# Precompiled host (tools\hosts\ComRunHost.cs, built with csc on first use) - no inline compiled code here.
. (Join-Path $PSScriptRoot '..\..\tools\hostbuild.ps1')
try { $hostExe = Get-RunHost 'ComRunHost' } catch { Write-Host $_.Exception.Message; exit 3 }

$hostArgs = @($dll)
if ($SkillArgs) { $hostArgs += @($SkillArgs) }
& $hostExe @hostArgs
$rc = $LASTEXITCODE
Write-Host "ExitCode=$rc"
exit $rc
