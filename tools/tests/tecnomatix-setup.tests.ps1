$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('txai-setup-test-' + [guid]::NewGuid().ToString('N'))
$saved = @{}
foreach ($name in 'LOCALAPPDATA', 'TX_TEST_ROOT', 'TX_TEST_MODE', 'UGII_BASE_DIR', 'UGII_ROOT_DIR') {
    $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

function Assert-True($Value, [string]$Message) {
    if (-not $Value) { throw $Message }
}

function Invoke-Check([string]$Script, [int]$ExpectedCode, [string]$ExpectedText) {
    $output = (& powershell -NoProfile -ExecutionPolicy Bypass -File $Script setup 2>&1 | Out-String)
    Assert-True ($LASTEXITCODE -eq $ExpectedCode) "Expected exit $ExpectedCode, got $LASTEXITCODE`n$output"
    Assert-True ($output.Contains($ExpectedText)) "Missing '$ExpectedText':`n$output"
    return $output
}

try {
    $tools = Join-Path $fixture 'tools'
    $client = Join-Path $fixture 'Tecnomatix\Tecnomatix-AI-Client'
    $clientTools = Join-Path $client 'tools'
    $stage = Join-Path $client 'deploy\TxAi'
    $install = Join-Path $fixture 'PS installation\eMPower'
    foreach ($dir in $tools, $clientTools, $stage, $install) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Copy-Item (Join-Path $repo 'tools\envcheck.ps1') $tools
    foreach ($file in 'txai.ps1', 'txai-config.ps1') {
        Copy-Item (Join-Path $repo "Tecnomatix\Tecnomatix-AI-Client\tools\$file") $clientTools
    }
    Set-Content (Join-Path $tools 'memcheck.ps1') 'function Assert-Memory { param($Scope) }'
    Set-Content (Join-Path $tools 'envdetect.ps1') @'
function Find-TxInstalls {
    if ($env:TX_TEST_MODE -ne 'absent') {
        [pscustomobject]@{ Dir = (Join-Path $env:TX_TEST_ROOT 'PS installation\eMPower'); Version = '9999.0' }
    }
}
function Get-Net48Pack { if ($env:TX_TEST_MODE -ne 'missing-pack') { 'test-pack' } }
function Get-Net48PackExpected { 'test-pack' }
function Find-VcRoot { 'test-vc' }
function Find-NxInstalls {}
function dotnet { 'test-sdk' }
'@
    Set-Content (Join-Path $clientTools 'package.ps1') @'
param([string]$TxInstallDir)
Add-Content (Join-Path $env:TX_TEST_ROOT 'build-count.txt') 'build'
if ($env:TX_TEST_MODE -eq 'build-failed') { throw 'simulated build failure' }
$stage = Join-Path $env:TX_TEST_ROOT 'Tecnomatix\Tecnomatix-AI-Client\deploy\TxAi'
Set-Content (Join-Path $stage 'TxAi.Contracts.dll') 'contracts'
if ($env:TX_TEST_MODE -ne 'partial-build') { Set-Content (Join-Path $stage 'TxAi.Addin.dll') 'addin' }
'@
    $env:LOCALAPPDATA = Join-Path $fixture 'profile'
    $env:TX_TEST_ROOT = $fixture
    $env:TX_TEST_MODE = ''
    $env:UGII_BASE_DIR = ''
    $env:UGII_ROOT_DIR = ''
    $runner = Join-Path $clientTools 'txai.ps1'
    $config = Join-Path $env:LOCALAPPDATA 'TxAi\txai.config.json'
    $contracts = Join-Path $stage 'TxAi.Contracts.dll'
    $addin = Join-Path $stage 'TxAi.Addin.dll'

    $null = Invoke-Check $runner 10 'Copy-Item -LiteralPath'
    Assert-True (Test-Path $addin) 'First setup did not build add-in'
    Assert-True (Test-Path $contracts) 'First setup did not build contracts'
    $settings = Get-Content $config -Raw | ConvertFrom-Json
    Assert-True ($settings.AllowedDirectories -contains (Join-Path $fixture 'Tecnomatix\Task')) 'Task whitelist missing'
    Assert-True (-not (Test-Path (Join-Path $install 'DotNetCommands'))) 'Setup performed administrator deployment'
    Write-Host 'PASS first setup builds, configures and prints administrator instructions without deploying'

    $timestamp = (Get-Item $config).LastWriteTimeUtc
    $null = Invoke-Check $runner 10 'Local preparation complete'
    Assert-True (@(Get-Content (Join-Path $fixture 'build-count.txt')).Count -eq 1) 'Repeated setup rebuilt complete DLLs'
    Assert-True ((Get-Item $config).LastWriteTimeUtc -eq $timestamp) 'Repeated setup rewrote config'
    Write-Host 'PASS repeated setup reuses DLLs and leaves unchanged config untouched'

    Remove-Item $addin
    $null = Invoke-Check $runner 10 'Local preparation complete'
    Assert-True (Test-Path $addin) 'Contracts-only stage did not rebuild the missing add-in'
    Write-Host 'PASS partial staging triggers rebuild'

    $settings.PipeName = 'TxAiSetupTest-' + [guid]::NewGuid().ToString('N')
    $settings.AllowedDirectories += (Join-Path $fixture 'existing-tasks')
    $settings | ConvertTo-Json | Set-Content $config
    $destination = Join-Path $install 'DotNetCommands\TxAi'
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    Copy-Item $addin $destination
    $null = Invoke-Check $runner 11 'AI Bridge is NOT running'
    $updated = Get-Content $config -Raw | ConvertFrom-Json
    Assert-True ($updated.PipeName -eq $settings.PipeName) 'Existing pipe name lost'
    Assert-True ($updated.AllowedDirectories -contains (Join-Path $fixture 'existing-tasks')) 'Existing whitelist lost'
    Write-Host 'PASS deployed but offline Bridge returns 11 and preserves user settings'

    Set-Content $config '{invalid'
    $null = Invoke-Check $runner 10 'config initialization failed'
    Assert-True ((Get-Content $config -Raw).Trim() -eq '{invalid') 'Invalid config overwritten'
    Remove-Item $config
    Write-Host 'PASS invalid JSON is reported and preserved'

    Remove-Item $addin
    $env:TX_TEST_MODE = 'build-failed'
    $null = Invoke-Check $runner 12 'simulated build failure'
    $env:TX_TEST_MODE = 'partial-build'
    $null = Invoke-Check $runner 12 'did not produce both'
    Write-Host 'PASS failed and incomplete builds return 12'

    $env:TX_TEST_MODE = 'missing-pack'
    $null = Invoke-Check $runner 10 'Developer Pack'
    Assert-True (-not (Test-Path $addin)) 'Setup built despite missing prerequisites'
    Write-Host 'PASS missing targeting pack blocks compilation'

    $env:TX_TEST_MODE = ''
    $output = (& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $tools 'envcheck.ps1') 2>&1 | Out-String)
    Assert-True ($output.Contains('automatically running txai.ps1 setup')) "envcheck did not invoke setup`n$output"
    Assert-True ($output.Contains('AI Bridge is NOT running')) "envcheck lost setup diagnostics`n$output"
    Assert-True ($output -match 'Tecnomatix\s+DETECTED, NOT READY') 'envcheck marked offline Bridge usable'
    Assert-True (Test-Path $addin) 'envcheck did not build missing add-in'
    Write-Host 'PASS envcheck automatically invokes setup and reports incomplete runtime readiness'

    $settings = Get-Content $config -Raw | ConvertFrom-Json
    $settings.PipeName = 'TxAiSetupTest-' + [guid]::NewGuid().ToString('N')
    $settings | ConvertTo-Json | Set-Content $config
    $job = Start-Job -ArgumentList $settings.PipeName -ScriptBlock {
        param($PipeName)
        $pipe = New-Object IO.Pipes.NamedPipeServerStream($PipeName)
        try {
            Write-Output 'listening'
            $pipe.WaitForConnection()
            $reader = New-Object IO.StreamReader($pipe)
            $writer = New-Object IO.StreamWriter($pipe)
            $writer.AutoFlush = $true
            $null = $reader.ReadLine()
            $writer.WriteLine('{"ok":true}')
        }
        finally { $pipe.Dispose() }
    }
    try {
        $ready = $false
        $deadline = [DateTime]::UtcNow.AddSeconds(15)
        while (-not $ready -and [DateTime]::UtcNow -lt $deadline) {
            $ready = (Receive-Job $job) -contains 'listening'
            if (-not $ready) { Start-Sleep -Milliseconds 100 }
        }
        Assert-True $ready 'Test pipe server did not start'
        $output = (& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $tools 'envcheck.ps1') 2>&1 | Out-String)
        Assert-True ($output -match 'Tecnomatix\s+USABLE') "Healthy Bridge was not usable`n$output"
        Assert-True ($output.Contains('Environment ready.')) 'Successful setup not reported'
        Write-Host 'PASS envcheck reports USABLE only after setup and Bridge ping succeed'
    }
    finally { Stop-Job $job; Remove-Job $job }

    $env:TX_TEST_MODE = 'absent'
    $output = (& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $tools 'envcheck.ps1') 2>&1 | Out-String)
    Assert-True (-not $output.Contains('automatically running txai.ps1 setup')) 'Setup ran without Tecnomatix'
    Assert-True ($output -match 'Tecnomatix\s+NOT DETECTED') 'Absent installation misreported'
    Write-Host 'PASS absent Tecnomatix skips automatic setup'
}
finally {
    foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}
