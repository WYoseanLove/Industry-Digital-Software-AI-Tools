<#
.SYNOPSIS
  Build and run Office (Excel / PowerPoint) COM-automation C# report skills (compiled to a DLL, loaded and invoked from PowerShell).

.DESCRIPTION
  setup : check Excel / PowerPoint COM registration, the C# compiler and 64-bit PowerShell (exit 10 when not ready).
  build : compile <Skill>.cs into <Skill>.dll (.NET Framework 4.x csc, C# 5, x64). Build failure exits 12.
          Set env OFFICERUN_PLATFORM=anycpu|x86 to override the default x64 target.
  run   : load <Skill>.dll, then on an STA thread call the single exported
          public static int Run(string[] args). The args are the remaining "key=value" strings.
          The script exit code equals the Run return value (13 when the skill throws).

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File Office\tools\officerun.ps1 build Office\Task\CsvToExcelReport\CsvToExcelReport.cs
  powershell -NoProfile -ExecutionPolicy Bypass -File Office\tools\officerun.ps1 run Office\Task\CsvToExcelReport\CsvToExcelReport.dll input=<data.csv> output=<report.xlsx>
#>
param(
    [Parameter(Mandatory, Position = 0)][ValidateSet('setup', 'build', 'run')][string]$Command,
    [Parameter(Position = 1)][string]$Path,
    [Parameter(Position = 2, ValueFromRemainingArguments)][string[]]$SkillArgs
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\tools\memcheck.ps1'); Assert-Memory 'Office'
$csc = Join-Path $env:windir 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'

if ($Command -eq 'setup') {
    $bad = New-Object System.Collections.Generic.List[string]
    function Ok($m)   { Write-Host "[OK] $m" }
    function Warn($m) { Write-Host "[!]  $m" }
    function Fail($m) { Write-Host "[X]  $m"; $bad.Add($m) }

    # 1. Office applications (out-of-process COM; the skill starts its own hidden instance)
    $found = 0
    foreach ($app in @(@('Excel.Application', 'Excel', 'EXCEL'), @('PowerPoint.Application', 'PowerPoint', 'POWERPNT'))) {
        $key = "Registry::HKEY_CLASSES_ROOT\$($app[0])\CLSID"
        if (Test-Path $key) {
            $found++
            $ver = $null
            $cv = "Registry::HKEY_CLASSES_ROOT\$($app[0])\CurVer"
            if (Test-Path $cv) { $ver = (Get-ItemProperty $cv).'(default)' }
            Ok "$($app[1]) COM registered ($ver)"
            if (Get-Process -Name $app[2] -ErrorAction SilentlyContinue) { Ok "$($app[1]) is already running; skills use an isolated or attached instance and never close the user's files." }
        }
        else { Warn "$($app[1]) is not registered. Skills that need $($app[1]) cannot run." }
    }
    if ($found -eq 0) { Fail 'Neither Excel nor PowerPoint is installed (ProgID not registered). Install Microsoft Office desktop edition.' }

    # 2. Toolchain
    if (-not [Environment]::Is64BitProcess) { Fail 'PowerShell is 32-bit; use 64-bit PowerShell.' }
    if (Test-Path $csc) { Ok "C# compiler: $csc" } else { Fail "csc.exe not found: $csc (install .NET Framework 4.x)." }

    if ($bad.Count -gt 0) { Write-Host "SETUP FAILED: $($bad.Count) problem(s)."; exit 10 }
    Write-Host 'SETUP OK'
    exit 0
}

if (-not $Path) { Write-Error "'$Command' requires a path."; exit 2 }

if ($Command -eq 'build') {
    if (-not (Test-Path $csc)) { Write-Error "csc.exe not found: $csc"; exit 3 }
    $platform = if ($env:OFFICERUN_PLATFORM) { $env:OFFICERUN_PLATFORM } else { 'x64' }
    $src = (Resolve-Path $Path).Path
    $dir = Split-Path $src -Parent
    $name = [IO.Path]::GetFileNameWithoutExtension($src)
    $out = Join-Path $dir "$name.dll"
    & $csc /nologo /target:library "/platform:$platform" /langversion:5 /optimize+ /r:Microsoft.CSharp.dll /r:System.Core.dll "/out:$out" $src
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
