param([switch]$PrintEnvironment)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = [Console]::OutputEncoding
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

# Desktop MCP clients may supply a minimal environment rather than a normal Windows logon environment.
$persisted = @{}
foreach ($target in @('Machine', 'User')) {
    foreach ($entry in [Environment]::GetEnvironmentVariables($target).GetEnumerator()) {
        if ($entry.Key -ne 'Path') { $persisted[$entry.Key] = [string]$entry.Value }
    }
}
$restored = New-Object System.Collections.Generic.List[string]
foreach ($name in $persisted.Keys) {
    if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name, 'Process'))) {
        [Environment]::SetEnvironmentVariable($name, $persisted[$name], 'Process')
        $restored.Add($name)
    }
}
$folders = @{
    'ProgramFiles' = [Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)
    'ProgramFiles(x86)' = [Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFilesX86)
    'ProgramW6432' = [Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)
    'CommonProgramFiles' = [Environment]::GetFolderPath([Environment+SpecialFolder]::CommonProgramFiles)
    'CommonProgramFiles(x86)' = [Environment]::GetFolderPath([Environment+SpecialFolder]::CommonProgramFilesX86)
    'APPDATA' = [Environment]::GetFolderPath([Environment+SpecialFolder]::ApplicationData)
    'LOCALAPPDATA' = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    'USERPROFILE' = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
    'ProgramData' = [Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)
    'ALLUSERSPROFILE' = [Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)
}
foreach ($name in $restored) {
    if ($persisted.ContainsKey($name)) {
        [Environment]::SetEnvironmentVariable($name, [Environment]::ExpandEnvironmentVariables($persisted[$name]), 'Process')
    }
}
foreach ($name in $folders.Keys) {
    if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name, 'Process')) -and $folders[$name]) {
        [Environment]::SetEnvironmentVariable($name, $folders[$name], 'Process')
        $restored.Add($name)
    }
}
$oldPath = $env:PATH
$paths = New-Object System.Collections.Generic.List[string]
$seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($source in @($oldPath, [Environment]::GetEnvironmentVariable('Path', 'Machine'), [Environment]::GetEnvironmentVariable('Path', 'User'))) {
    foreach ($item in ([Environment]::ExpandEnvironmentVariables([string]$source) -split ';')) {
        $item = $item.Trim()
        if ($item -and $seen.Add($item)) { $paths.Add($item) }
    }
}
$env:PATH = $paths -join ';'
$oldExtensions = $env:PATHEXT
$extensions = New-Object System.Collections.Generic.List[string]
$seenExtensions = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($source in @($oldExtensions, [Environment]::GetEnvironmentVariable('PATHEXT', 'Machine'), [Environment]::GetEnvironmentVariable('PATHEXT', 'User'))) {
    foreach ($item in ([string]$source -split ';')) {
        $item = $item.Trim()
        if ($item -and $seenExtensions.Add($item)) { $extensions.Add($item) }
    }
}
$env:PATHEXT = $extensions -join ';'
if ($PrintEnvironment) {
    $environment = @{}
    foreach ($entry in [Environment]::GetEnvironmentVariables('Process').GetEnumerator()) {
        $environment[$entry.Key] = [string]$entry.Value
    }
    @{ environment = $environment; restoredCount = $restored.Count; pathChanged = ($env:PATH -ne $oldPath);
        extensionsChanged = ($env:PATHEXT -ne $oldExtensions) } |
        ConvertTo-Json -Depth 5 -Compress
    exit 0
}
if ($restored.Count -gt 0 -or $env:PATH -ne $oldPath -or $env:PATHEXT -ne $oldExtensions) {
    Write-Host "[MCP] Restored $($restored.Count) missing process environment variables; merged Windows Machine/User PATH/PATHEXT (process only)."
}

$request = $env:MFG_MCP_REQUEST | ConvertFrom-Json
$env:MFG_TASK_HINT = $request.taskHint
$runners = @{
    NX = 'NX\tools\nxrun.ps1'
    Office = 'Office\tools\officerun.ps1'
    Catia = 'Catia\tools\catrun.ps1'
    Vismockup = 'Vismockup\tools\vmrun.ps1'
    Tecnomatix = 'Tecnomatix\Tecnomatix-AI-Client\tools\txai.ps1'
}
if ($request.command -eq 'environment') {
    & (Join-Path $root 'tools\envcheck.ps1')
    exit $LASTEXITCODE
}
if (-not $runners.ContainsKey($request.product)) { throw 'Unknown product.' }
if ($request.command -notin @('setup', 'ping', 'build', 'run')) { throw 'Unknown command.' }
$runner = Join-Path $root $runners[$request.product]
if ($request.product -eq 'Tecnomatix') {
    $parameters = @{ Command = $request.command }
    if ($request.command -in @('build', 'run')) {
        $parameters.Skill = $request.skill
        if ($request.command -eq 'run') {
            $parameters.ArgsJson = ConvertTo-Json -InputObject $request.argsJson -Depth 30 -Compress
            $parameters.TimeoutMs = $request.timeoutSeconds * 1000
        }
    }
    & $runner @parameters
} else {
    $parameters = @{ Command = $request.command }
    if ($request.command -in @('build', 'run')) {
        $extension = if ($request.command -eq 'run') { '.dll' } elseif ($request.product -eq 'NX') { '.cpp' } else { '.cs' }
        $parameters.Path = Join-Path $root "$($request.product)\Task\$($request.skill)\$($request.skill)$extension"
        if ($request.command -eq 'run') {
            if ($request.product -eq 'NX') { $parameters.NxArgs = [string[]]$request.args }
            else { $parameters.SkillArgs = [string[]]$request.args }
        }
    }
    & $runner @parameters
}
exit $LASTEXITCODE
