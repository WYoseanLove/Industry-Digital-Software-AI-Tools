# Compiles tools\hosts\<Name>.cs into a per-user cache on first use (and when the source changes); returns the exe path.
$script:HostToolsRoot = $PSScriptRoot

function Get-RunHost {
    param([Parameter(Mandatory)][string]$Name)

    $csc = Join-Path $env:windir 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (-not (Test-Path $csc)) { throw "csc.exe not found: $csc (install .NET Framework 4.x)." }

    $src = Join-Path $script:HostToolsRoot "hosts\$Name.cs"
    if (-not (Test-Path $src)) { throw "Host source not found: $src" }

    $base = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { $env:TEMP }
    $dir = Join-Path $base 'Industry-Digital-Software-AI-Tools\bin'
    $exe = Join-Path $dir "$Name.exe"

    $stale = (-not (Test-Path $exe)) -or ((Get-Item $exe).LastWriteTimeUtc -lt (Get-Item $src).LastWriteTimeUtc)
    if ($stale) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $tmp = Join-Path $dir "$Name.$([guid]::NewGuid().ToString('N')).tmp.exe"
        & $csc /nologo /target:exe /platform:x64 /optimize+ "/out:$tmp" $src | Out-Host
        if ($LASTEXITCODE -ne 0) { Remove-Item $tmp -ErrorAction SilentlyContinue; throw "Failed to compile $src" }
        try { Move-Item $tmp $exe -Force }
        catch {
            Remove-Item $tmp -ErrorAction SilentlyContinue
            if (-not (Test-Path $exe)) { throw }
        }
    }
    return $exe
}
