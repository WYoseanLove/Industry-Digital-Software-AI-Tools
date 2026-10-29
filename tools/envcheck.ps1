<#
.SYNOPSIS
  Industry-Digital-Software-AI-Tools environment and software check (version independent).

.DESCRIPTION
  detect  (default): report build prerequisites and which products are installed AND usable
                     (Vismockup, Office, CATIA, NX, Tecnomatix). Exit 0 if at least one product is usable, else 10.
  install          : fix what can be fixed. Admin-only steps run ONLY when this PowerShell is already elevated;
                     otherwise the exact commands are printed for the user. Never self-elevates.
                     - winget: .NET Framework 4.8 Developer Pack, .NET SDK, VS Build Tools (C++ x64)
                     - NX: runs "Deploy-Application.exe -Section 3" (installs the UGOPEN folder) when -NxDeployDir
                       (or env NX_DEPLOY_DIR) points at the folder holding Deploy-Application.exe
                     - NX: sets UGII_BASE_DIR / UGII_ROOT_DIR at user scope (setx, no admin needed)

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File <Root>\tools\envcheck.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File <Root>\tools\envcheck.ps1 install -NxDeployDir "<folder with Deploy-Application.exe>"
#>
param(
    [Parameter(Position = 0)][ValidateSet('detect', 'install')][string]$Command = 'detect',
    [string]$NxDeployDir
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'memcheck.ps1'); Assert-Memory ([regex]::Unescape('\u73af\u5883'))
. (Join-Path $PSScriptRoot 'envdetect.ps1')
$RepoRoot = Split-Path -Parent $PSScriptRoot

# ---------------------------------------------------------------- helpers
function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Resolve a COM ProgID to its server file. Returns Registered / Exe / Exists / Bits.
function Get-ComServer([string]$ProgId) {
    $r = [ordered]@{ Registered = $false; Exe = $null; Exists = $false; Bits = $null; CurVer = $null }
    $k = "Registry::HKEY_CLASSES_ROOT\$ProgId\CLSID"
    if (-not (Test-Path $k)) { return $r }
    $clsid = (Get-ItemProperty $k).'(default)'
    $r.Registered = $true
    $cv = "Registry::HKEY_CLASSES_ROOT\$ProgId\CurVer"
    if (Test-Path $cv) { $r.CurVer = (Get-ItemProperty $cv).'(default)' }
    $views = @(
        @{ Root = 'Registry::HKEY_CLASSES_ROOT\CLSID'; Bits = 64 },
        @{ Root = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Classes\WOW6432Node\CLSID'; Bits = 32 }
    )
    foreach ($v in $views) {
        foreach ($sub in 'LocalServer32', 'InprocServer32') {
            $p = "$($v.Root)\$clsid\$sub"
            if (-not (Test-Path $p)) { continue }
            $raw = [string](Get-ItemProperty $p).'(default)'
            if (-not $raw) { continue }
            if ($raw -match '^"([^"]+)"') { $exe = $Matches[1] }
            elseif ($raw -match '^(.+?\.(exe|dll))') { $exe = $Matches[1] }
            else { $exe = $raw }
            $r.Exe = $exe; $r.Bits = $v.Bits; $r.Exists = (Test-Path $exe)
            return $r
        }
    }
    return $r
}

function Get-FileVer([string]$Path) {
    try { (Get-Item $Path -ErrorAction Stop).VersionInfo.ProductVersion } catch { $null }
}

# ---------------------------------------------------------------- build prerequisites
$cscPath = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$vcRoot = Find-VcRoot
$pack48 = Get-Net48Pack
if (-not $pack48) { $pack48Expected = Get-Net48PackExpected } else { $pack48Expected = $pack48 }
$hasDotnet = [bool](Get-Command dotnet -ErrorAction SilentlyContinue)
$dotnetVer = $null
if ($hasDotnet) { $dotnetVer = (& dotnet --version 2>$null) | Select-Object -First 1 }

$prereq = [ordered]@{
    'PowerShell x64'              = @{ Ok = [Environment]::Is64BitProcess; Detail = "PS $($PSVersionTable.PSVersion), 64-bit=$([Environment]::Is64BitProcess)"; Fix = 'Start the 64-bit Windows PowerShell / VS Code.' ; Winget = $null }
    'C# compiler (csc, .NET 4.x)' = @{ Ok = (Test-Path $cscPath); Detail = $cscPath; Fix = 'Enable .NET Framework 4.x (built into Windows 10/11).'; Winget = $null }
    '.NET Framework 4.8 Dev Pack' = @{ Ok = [bool]$pack48; Detail = $pack48Expected; Fix = 'winget install --id Microsoft.DotNet.Framework.DeveloperPack_4 -e'; Winget = 'Microsoft.DotNet.Framework.DeveloperPack_4' }
    '.NET SDK (dotnet)'           = @{ Ok = $hasDotnet; Detail = $(if ($hasDotnet) { "dotnet $dotnetVer" } else { 'not found' }); Fix = 'winget install --id Microsoft.DotNet.SDK.8 -e'; Winget = 'Microsoft.DotNet.SDK.8' }
    'MSVC C++ x64 (Build Tools)'  = @{ Ok = [bool]$vcRoot; Detail = $(if ($vcRoot) { $vcRoot } else { 'not found' }); Fix = 'winget install --id Microsoft.VisualStudio.2022.BuildTools -e --override "--passive --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"'; Winget = 'Microsoft.VisualStudio.2022.BuildTools' }
}

# ---------------------------------------------------------------- product detection
$products = New-Object System.Collections.Generic.List[object]
function Add-Product($Name, $Detected, $Version, $Issues, $Detail, $Runner) {
    $products.Add([pscustomobject]@{
            Product  = $Name
            Detected = $Detected
            Version  = $Version
            Usable   = ($Detected -and ($Issues.Count -eq 0))
            Issues   = ($Issues -join ' | ')
            Detail   = $Detail
            Runner   = $Runner
        })
}
function Need([string[]]$Names) {
    $m = @(); foreach ($n in $Names) { if (-not $prereq[$n].Ok) { $m += "missing prerequisite: $n" } }
    $m
}

# --- Vismockup (COM VFFrame.Application)
$vm = Get-ComServer 'VFFrame.Application'
$iss = @(Need @('PowerShell x64', 'C# compiler (csc, .NET 4.x)'))
if ($vm.Registered -and $vm.Exe -and -not $vm.Exists) { $iss += 'COM server file missing (stale registration)' }
Add-Product 'Vismockup' ($vm.Registered -and $vm.Exists) $(if ($vm.Exists) { Get-FileVer $vm.Exe }) $iss $vm.Exe 'Vismockup\tools\vmrun.ps1'

# --- Office (Excel + PowerPoint COM)
$xl = Get-ComServer 'Excel.Application'
$pp = Get-ComServer 'PowerPoint.Application'
$iss = @(Need @('PowerShell x64', 'C# compiler (csc, .NET 4.x)'))
if (-not ($xl.Registered -and $xl.Exists)) { $iss += 'Excel not found' }
if (-not ($pp.Registered -and $pp.Exists)) { $iss += 'PowerPoint not found (Excel-only reports still work)' }
$offVer = if ($xl.Exists) { Get-FileVer $xl.Exe } else { $null }
$offDet = "Excel=$($xl.Exe); PowerPoint=$($pp.Exe)"
Add-Product 'Office' ($xl.Registered -and $xl.Exists) $offVer $iss $offDet 'Office\tools\officerun.ps1'

# --- CATIA V5 (COM CATIA.Application, fallback: scan Dassault Systemes\B*)
$ct = Get-ComServer 'CATIA.Application'
$cnext = $null
if ($ct.Registered -and $ct.Exists) { $cnext = $ct.Exe }
else {
    foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not $root) { continue }
        $c = Get-ChildItem (Join-Path $root 'Dassault Systemes\B*\win_b64\code\bin\CNEXT.exe') -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending | Select-Object -First 1
        if ($c) { $cnext = $c.FullName; break }
    }
}
$iss = @(Need @('PowerShell x64', 'C# compiler (csc, .NET 4.x)'))
if ($cnext -and -not $ct.Registered) { $iss += 'CATIA files found but COM ProgID not registered (run CNEXT /regserver as admin)' }
$ctVer = $null
if ($cnext -and $cnext -match '\\(B\d+)\\') { $ctVer = 'V5-6 ' + $Matches[1] }
Add-Product 'CATIA' ([bool]$cnext) $ctVer $iss $cnext 'Catia\tools\catrun.ps1'

# --- Siemens NX
$nxInstalls = @(Find-NxInstalls)
$nxBase = $env:UGII_BASE_DIR
if (-not $nxBase -and $nxInstalls.Count -gt 0) { $nxBase = $nxInstalls[-1].Path }
$nxDetected = ($nxInstalls.Count -gt 0) -or ($nxBase -and (Test-Path (Join-Path $nxBase 'NXBIN')))
$iss = @(Need @('PowerShell x64', 'MSVC C++ x64 (Build Tools)'))
$nxOpenOk = $false
if ($nxDetected -and $nxBase) {
    $ug = Join-Path $nxBase 'UGOPEN'
    $need = @('NXOpen\Session.hxx', 'uf.h', 'libnxopencpp.lib', 'libufun.lib', 'libnxopencpp_assemblies.lib')
    $miss = @($need | Where-Object { -not (Test-Path (Join-Path $ug $_)) })
    $nxOpenOk = ($miss.Count -eq 0)
    if (-not $nxOpenOk) { $iss += 'NX Open (UGOPEN) folder missing/incomplete -> needs ADMIN: Deploy-Application.exe -Section 3' }
    if (-not $env:UGII_BASE_DIR) { $iss += "UGII_BASE_DIR not set (setx UGII_BASE_DIR `"$nxBase`")" }
    elseif (-not (Test-Path $env:UGII_BASE_DIR)) { $iss += 'UGII_BASE_DIR points to a missing folder' }
    if (-not $env:UGII_ROOT_DIR) { $iss += "UGII_ROOT_DIR not set (setx UGII_ROOT_DIR `"$nxBase\NXBIN`")" }
    elseif (-not (Test-Path $env:UGII_ROOT_DIR)) { $iss += 'UGII_ROOT_DIR points to a missing folder' }
}
$nxVer = $null
if ($nxBase) {
    $nxSel = $nxInstalls | Where-Object { $_.Path -ieq $nxBase.TrimEnd('\') } | Select-Object -First 1
    if ($nxSel -and $nxSel.Version) { $nxVer = $nxSel.Version }
    elseif ($nxBase -match 'NX\s*(\d+)') { $nxVer = $Matches[1] }
    if ($nxInstalls.Count -gt 1) { $nxVer = "$nxVer (also installed: " + (($nxInstalls | Where-Object { $_.Path -ine $nxBase.TrimEnd('\') } | ForEach-Object { $_.Version }) -join ', ') + ')' }
}
Add-Product 'NX' $nxDetected $nxVer $iss $nxBase 'NX\tools\nxrun.ps1'

# --- Tecnomatix Process Simulate
$txAll = @(Find-TxInstalls)
$tx = $txAll | Select-Object -Last 1
$iss = @(Need @('PowerShell x64', '.NET SDK (dotnet)', '.NET Framework 4.8 Dev Pack'))
$txVer = $null
if ($tx) {
    $txVer = $tx.Version
    Write-Host '[..] Tecnomatix detected: automatically running txai.ps1 setup (local build + config; no elevation).'
    $txRunner = Join-Path $RepoRoot 'Tecnomatix\Tecnomatix-AI-Client\tools\txai.ps1'
    & $txRunner setup | Out-Host
    $txSetupExit = $LASTEXITCODE
    if ($txSetupExit -ne 0) {
        $iss += "Automatic txai.ps1 setup exited with $txSetupExit -> follow the setup instructions above, then rerun envcheck.ps1"
    }
    $txAddin = Get-ChildItem (Join-Path $tx.Dir 'DotNetCommands') -Recurse -Filter 'TxAi.Addin.dll' -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $txAddin) {
        $iss += 'AI Bridge add-in not installed -> needs ADMIN copy of Tecnomatix-AI-Client\deploy\TxAi (see setup output above)'
    }
}
Add-Product 'Tecnomatix' ([bool]$tx) $txVer $iss $(if ($tx) { $tx.Dir }) 'Tecnomatix\Tecnomatix-AI-Client\tools\txai.ps1'

# ---------------------------------------------------------------- report
$isAdmin = Test-Admin
Write-Host ''
Write-Host "== Industry-Digital-Software-AI-Tools environment check =="
Write-Host "OS: $([Environment]::OSVersion.VersionString)   Admin: $isAdmin   Repo: $RepoRoot"
Write-Host ''
Write-Host '-- Build prerequisites --'
foreach ($k in $prereq.Keys) {
    $p = $prereq[$k]
    $tag = if ($p.Ok) { '[OK]' } else { '[X] ' }
    Write-Host ("{0} {1,-30} {2}" -f $tag, $k, $p.Detail)
}
Write-Host ''
Write-Host '-- Software --'
foreach ($p in $products) {
    $state = if ($p.Usable) { 'USABLE' } elseif ($p.Detected) { 'DETECTED, NOT READY' } else { 'NOT DETECTED' }
    Write-Host ("{0,-11} {1,-20} version={2}" -f $p.Product, $state, $(if ($p.Version) { $p.Version } else { '-' }))
    if ($p.Detail) { Write-Host "            path: $($p.Detail)" }
    if ($p.Issues) { foreach ($i in ($p.Issues -split ' \| ')) { Write-Host "            [!] $i" } }
}
$usable = @($products | Where-Object { $_.Usable })
Write-Host ''
if ($usable.Count -gt 0) {
    Write-Host ('Usable now: ' + (($usable | ForEach-Object { $_.Product }) -join ', '))
    foreach ($u in $usable) { Write-Host ("  {0,-11} runner: {1}" -f $u.Product, $u.Runner) }
}
else { Write-Host 'No product is usable yet.' }
$unusable = @($products | Where-Object { -not $_.Usable })
if ($unusable.Count -gt 0) { Write-Host ('Not usable: ' + (($unusable | ForEach-Object { $_.Product }) -join ', ')) }

# ---------------------------------------------------------------- install
if ($Command -eq 'install') {
    Write-Host ''
    Write-Host '== install =='
    $manual = New-Object System.Collections.Generic.List[string]
    $hasWinget = [bool](Get-Command winget -ErrorAction SilentlyContinue)

    # which prerequisites are actually needed by detected products (or all when nothing detected)
    $wanted = @{}
    foreach ($p in $products) {
        if ($p.Product -in 'Vismockup', 'Office', 'CATIA') { }
        if ($p.Product -eq 'NX' -and $p.Detected) { $wanted['MSVC C++ x64 (Build Tools)'] = $true }
        if ($p.Product -eq 'Tecnomatix' -and $p.Detected) { $wanted['.NET SDK (dotnet)'] = $true; $wanted['.NET Framework 4.8 Dev Pack'] = $true }
    }
    foreach ($k in $prereq.Keys) {
        $p = $prereq[$k]
        if ($p.Ok -or -not $wanted.ContainsKey($k) -or -not $p.Winget) { continue }
        if ($isAdmin -and $hasWinget) {
            Write-Host "[..] installing $k via winget"
            if ($p.Winget -like '*BuildTools') {
                & winget install --id $p.Winget -e --accept-package-agreements --accept-source-agreements --override '--passive --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended'
            }
            else {
                & winget install --id $p.Winget -e --accept-package-agreements --accept-source-agreements
            }
        }
        else { $manual.Add("[admin] $k : $($p.Fix)") }
    }

    # NX: UGOPEN deploy + user-scope env vars
    $nx = $products | Where-Object { $_.Product -eq 'NX' }
    if ($nx.Detected -and $nxBase) {
        if (-not $nxOpenOk) {
            if (-not $NxDeployDir) { $NxDeployDir = $env:NX_DEPLOY_DIR }
            $deploy = if ($NxDeployDir) { Join-Path $NxDeployDir 'Deploy-Application.exe' } else { $null }
            if ($deploy -and (Test-Path $deploy) -and $isAdmin) {
                Write-Host "[..] running: Deploy-Application.exe -Section 3  (in $NxDeployDir)"
                Push-Location $NxDeployDir
                try { & $deploy -Section 3 | Out-Host } finally { Pop-Location }
            }
            else {
                $manual.Add('[admin] NX Open (UGOPEN) is not installed. In an ADMIN command prompt: cd <CAD\<NX release> folder>  (find it in the Siemens_NXCAD file, "software dump location"), then run: Deploy-Application.exe -Section 3')
                $manual.Add('        then re-run: envcheck.ps1 install   (or pass -NxDeployDir <folder> from an elevated PowerShell to automate it)')
            }
        }
        if (-not $env:UGII_BASE_DIR) { & setx UGII_BASE_DIR $nxBase | Out-Null; Write-Host "[OK] setx UGII_BASE_DIR $nxBase (open a NEW terminal)" }
        if (-not $env:UGII_ROOT_DIR) { & setx UGII_ROOT_DIR (Join-Path $nxBase 'NXBIN') | Out-Null; Write-Host "[OK] setx UGII_ROOT_DIR $(Join-Path $nxBase 'NXBIN') (open a NEW terminal)" }
    }

    if ($manual.Count -gt 0) {
        Write-Host ''
        Write-Host 'Manual steps (this shell is not elevated / tool missing; the agent never self-elevates):'
        $manual | ForEach-Object { Write-Host "  $_" }
        if (-not $isAdmin) { Write-Host '  Tip: restart VS Code with "Run as administrator", then re-run install.' }
    }
    Write-Host 'Re-run "envcheck.ps1" (detect) in a NEW terminal to confirm.'
}

if ($usable.Count -gt 0) { exit 0 } else { exit 10 }
