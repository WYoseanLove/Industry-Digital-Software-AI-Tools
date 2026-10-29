# Builds the solution, stages the add-in under .\deploy\ and publishes sample task DLLs to <repo>\Tecnomatix\Task\
param(
    [string]$Configuration = 'Release',
    [string]$TxInstallDir
)

$ErrorActionPreference = 'Stop'
if (-not $TxInstallDir) { throw 'Pass -TxInstallDir <PS install>\eMPower\ (folder that contains Tecnomatix.Engineering.dll).' }
$root = Split-Path -Parent $PSScriptRoot
# Doubled trailing backslash keeps Windows PowerShell 5.1 from escaping the closing quote.
dotnet build (Join-Path $root 'TxAi.sln') -c $Configuration "-p:TxInstallDir=$($TxInstallDir.TrimEnd('\'))\\"
if ($LASTEXITCODE -ne 0) { throw 'Build failed.' }

$deploy = Join-Path $root 'deploy'
if (Test-Path $deploy) { Remove-Item $deploy -Recurse -Force }
$addinDir = Join-Path $deploy 'TxAi'
New-Item -ItemType Directory -Path $addinDir -Force | Out-Null

$addinOut = Join-Path $root "src\TxAi.Addin\bin\$Configuration\net48"
Copy-Item (Join-Path $addinOut 'TxAi.Addin.dll') $addinDir
Copy-Item (Join-Path $addinOut 'TxAi.Contracts.dll') $addinDir

$taskDir = Join-Path (Split-Path -Parent $root) 'Task'
New-Item -ItemType Directory -Path $taskDir -Force | Out-Null
Copy-Item (Join-Path $root "src\TxAi.Tasks.Samples\bin\$Configuration\net48\TxAi.Tasks.Samples.dll") $taskDir

Write-Host "Add-in staged: $addinDir"
Write-Host "Task DLLs:     $taskDir"
Write-Host "1. Copy the 'TxAi' folder to <PS install>\eMPower\DotNetCommands\ (admin needed once)."
Write-Host '2. txai.ps1 setup initializes the user config and task whitelist automatically.'
