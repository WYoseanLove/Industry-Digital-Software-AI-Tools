function Initialize-TxAiConfig {
    param(
        [Parameter(Mandatory = $true)][string]$TaskRoot,
        [string]$ConfigPath = (Join-Path $env:LOCALAPPDATA 'TxAi\txai.config.json')
    )

    $TaskRoot = [IO.Path]::GetFullPath($TaskRoot).TrimEnd('\')
    $changed = $false
    $exists = Test-Path -LiteralPath $ConfigPath
    $config = if ($exists) {
        Get-Content -LiteralPath $ConfigPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } else { New-Object psobject }
    if ($null -eq $config -or $config -isnot [pscustomobject]) {
        throw "Invalid config object: $ConfigPath. Existing file was not changed."
    }

    $defaults = [ordered]@{ PipeName = 'TxAiClient'; DefaultTimeoutMs = 120000; AutoStart = $false; AllowedDirectories = @() }
    foreach ($name in $defaults.Keys) {
        if (-not $config.PSObject.Properties[$name]) {
            $config | Add-Member NoteProperty $name $defaults[$name]
            $changed = $true
        }
    }
    if ($config.PipeName -isnot [string] -or [string]::IsNullOrWhiteSpace($config.PipeName)) {
        throw "Invalid PipeName in $ConfigPath. Existing file was not changed."
    }
    $directories = @($config.AllowedDirectories)
    foreach ($directory in $directories) {
        if ($directory -isnot [string] -or [string]::IsNullOrWhiteSpace($directory)) {
            throw "Invalid AllowedDirectories in $ConfigPath. Existing file was not changed."
        }
    }
    if (-not ($directories | Where-Object { $_.TrimEnd('\') -ieq $TaskRoot })) {
        $config.AllowedDirectories = $directories + $TaskRoot
        $changed = $true
    }
    if ($changed) {
        New-Item -ItemType Directory -Path (Split-Path $ConfigPath -Parent) -Force -ErrorAction Stop | Out-Null
        $config | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $ConfigPath -Encoding UTF8 -ErrorAction Stop
        Write-Host "[OK] Config initialized/updated: $ConfigPath"
        Write-Host '[!] If Process Simulate is already running, save your work and restart it, then click AI Bridge to reload the config.'
    } else { Write-Host "[OK] Config: $ConfigPath" }

    [pscustomobject]@{ Path = $ConfigPath; Changed = $changed; PipeName = $config.PipeName }
}