# Shared product / toolchain discovery for all runners (dot-source it).
# Only defines read-only functions: no registry writes, no downloads, no process launching except vswhere.exe.
# Nothing here assumes C:\Program Files or a folder-name version: install roots come from environment
# variables and fixed drives, versions come from the product's own file version info.

# Candidate install roots: ProgramW6432 / ProgramFiles / ProgramFiles(x86), then every fixed drive
# (<drive>\Program Files, <drive>\Program Files (x86), <drive>\).
function Get-ProgramRoots {
    $list = New-Object System.Collections.Generic.List[string]
    $add = {
        param($p)
        if (-not $p) { return }
        $p = $p.TrimEnd('\')
        if (-not $p) { return }
        if (-not ($list -contains $p) -and (Test-Path -LiteralPath $p)) { $list.Add($p) }
    }
    foreach ($r in @($env:ProgramW6432, $env:ProgramFiles, ${env:ProgramFiles(x86)})) { & $add $r }
    try {
        foreach ($d in [IO.DriveInfo]::GetDrives()) {
            if ($d.DriveType -ne [IO.DriveType]::Fixed -or -not $d.IsReady) { continue }
            $rootDir = $d.RootDirectory.FullName
            & $add (Join-Path $rootDir 'Program Files')
            & $add (Join-Path $rootDir 'Program Files (x86)')
            & $add $rootDir
        }
    }
    catch { }
    return $list.ToArray()
}

function Get-FileProductVersion([string]$Path) {
    try {
        $v = (Get-Item -LiteralPath $Path -ErrorAction Stop).VersionInfo
        if ($v.ProductVersion) { return $v.ProductVersion.Trim() }
        if ($v.FileVersion) { return $v.FileVersion.Trim() }
    }
    catch { }
    return $null
}

# Turns "2512", "2512.0.1.3" or "NX 2512" into a [version] usable for sorting (0.0 when no digits).
function ConvertTo-VersionObject([string]$Text) {
    if ($Text -and $Text -match '(\d+(\.\d+){0,3})') {
        $t = $Matches[1]
        if ($t -notmatch '\.') { $t += '.0' }
        try { return [version]$t } catch { }
    }
    return [version]'0.0'
}

# Siemens NX installs, oldest first. UGII_BASE_DIR (if set) is always a candidate.
# Each item: Path, Version (from NXBIN\ugraf.exe, folder-name digits only as a fallback), Sort.
function Find-NxInstalls {
    $cands = New-Object System.Collections.Generic.List[string]
    if ($env:UGII_BASE_DIR) { $cands.Add($env:UGII_BASE_DIR.TrimEnd('\')) }
    foreach ($root in (Get-ProgramRoots)) {
        $sie = Join-Path $root 'Siemens'
        if (-not (Test-Path -LiteralPath $sie)) { continue }
        foreach ($d in (Get-ChildItem -LiteralPath $sie -Directory -ErrorAction SilentlyContinue)) { $cands.Add($d.FullName) }
    }
    $seen = @{}
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($c in $cands) {
        $k = $c.ToLowerInvariant()
        if ($seen.ContainsKey($k)) { continue }
        $seen[$k] = $true
        $ugraf = Join-Path $c 'NXBIN\ugraf.exe'
        $hasBin = Test-Path -LiteralPath $ugraf
        if (-not ($hasBin -or (Test-Path -LiteralPath (Join-Path $c 'UGOPEN\uf.h')))) { continue }
        $ver = if ($hasBin) { Get-FileProductVersion $ugraf } else { $null }
        if (-not $ver -and $c -match 'NX\s*(\d+)') { $ver = $Matches[1] }
        $out.Add([pscustomobject]@{ Path = $c; Version = $ver; Sort = (ConvertTo-VersionObject $ver) })
    }
    return @($out | Sort-Object Sort)
}

# Tecnomatix Process Simulate installs, oldest first. Env TX_INSTALL_DIR (the eMPower folder) is a candidate too.
# Each item: Dir (folder holding Tecnomatix.Engineering.dll, no trailing backslash), Dll, Version, Sort.
function Find-TxInstalls {
    $dlls = New-Object System.Collections.Generic.List[string]
    if ($env:TX_INSTALL_DIR) {
        $f = Join-Path $env:TX_INSTALL_DIR.TrimEnd('\') 'Tecnomatix.Engineering.dll'
        if (Test-Path -LiteralPath $f) { $dlls.Add($f) }
    }
    foreach ($root in (Get-ProgramRoots)) {
        $parents = @($root, (Join-Path $root 'Siemens')) | Where-Object { Test-Path -LiteralPath $_ }
        foreach ($p in $parents) {
            foreach ($d in (Get-ChildItem -LiteralPath $p -Directory -Filter 'Tecnomatix*' -ErrorAction SilentlyContinue)) {
                $f = Join-Path $d.FullName 'eMPower\Tecnomatix.Engineering.dll'
                if (Test-Path -LiteralPath $f) { $dlls.Add($f) }
            }
        }
    }
    $seen = @{}
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($f in $dlls) {
        $k = $f.ToLowerInvariant()
        if ($seen.ContainsKey($k)) { continue }
        $seen[$k] = $true
        $ver = Get-FileProductVersion $f
        $out.Add([pscustomobject]@{ Dir = (Split-Path -Parent $f); Dll = $f; Version = $ver; Sort = (ConvertTo-VersionObject $ver) })
    }
    return @($out | Sort-Object Sort)
}

# .NET Framework 4.8 targeting pack folder, or $null.
function Get-Net48Pack {
    foreach ($pf in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
        if (-not $pf) { continue }
        $p = Join-Path $pf 'Reference Assemblies\Microsoft\Framework\.NETFramework\v4.8'
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

# Where the targeting pack is expected (for messages only).
function Get-Net48PackExpected {
    $pf = if (${env:ProgramFiles(x86)}) { ${env:ProgramFiles(x86)} } else { $env:ProgramFiles }
    return (Join-Path $pf 'Reference Assemblies\Microsoft\Framework\.NETFramework\v4.8')
}

# Visual Studio / Build Tools installation that has the C++ x64 toolset and vcvars64.bat, or $null.
function Find-VcRoot {
    $vsw = $null
    foreach ($pf in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
        if (-not $pf) { continue }
        $c = Join-Path $pf 'Microsoft Visual Studio\Installer\vswhere.exe'
        if (Test-Path -LiteralPath $c) { $vsw = $c; break }
    }
    if (-not $vsw) {
        $cmd = Get-Command vswhere.exe -ErrorAction SilentlyContinue
        if ($cmd) { $vsw = $cmd.Source }
    }
    if (-not $vsw) { return $null }
    $root = (& $vsw -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath) | Select-Object -First 1
    if ($root -and (Test-Path -LiteralPath (Join-Path $root 'VC\Auxiliary\Build\vcvars64.bat'))) { return $root }
    return $null
}

function Find-VcVars64 {
    $root = Find-VcRoot
    if ($root) { return (Join-Path $root 'VC\Auxiliary\Build\vcvars64.bat') }
    return $null
}

# Loads the x64 MSVC environment (INCLUDE / LIB / PATH ...) into the CURRENT process, so cl.exe can be called
# directly. Uses vcvars64.bat exactly as Visual Studio's own prompt does; no script file is written.
function Import-VcEnvironment([string]$VcVars) {
    $lines = & cmd.exe /d /c "call `"$VcVars`" >nul 2>&1 && set"
    if ($LASTEXITCODE -ne 0) { return $false }
    foreach ($l in $lines) {
        $i = $l.IndexOf('=')
        if ($i -le 0) { continue }
        Set-Item -LiteralPath ("Env:" + $l.Substring(0, $i)) -Value $l.Substring($i + 1)
    }
    return [bool](Get-Command cl.exe -ErrorAction SilentlyContinue)
}

function Find-Csc {
    $p = Join-Path $env:windir 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (Test-Path -LiteralPath $p) { return $p }
    return $null
}
