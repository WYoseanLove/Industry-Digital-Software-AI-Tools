# Single entry point for the Tecnomatix AI skill workflow. Every command re-validates the environment first.
#   txai.ps1 setup                         check/repair environment
#   txai.ps1 ping                          is AI Bridge running?
#   txai.ps1 build <Skill>                 compile Task\<Skill>\ (creates the csproj if missing)
#   txai.ps1 run <Skill> [-ArgsJson '{}']  build-free: ping, then run Task\<Skill>\<Skill>.dll in Process Simulate
# Exit codes: 0 ok, 10 environment not ready, 11 AI Bridge not running, 12 build failed, 13 skill failed.
param(
    [Parameter(Mandatory = $true, Position = 0)][ValidateSet('setup', 'ping', 'build', 'run')][string]$Command,
    [Parameter(Position = 1)][string]$Skill,
    [string]$ArgsJson = '{}',
    [int]$TimeoutMs = 120000
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\..\tools\memcheck.ps1'); Assert-Memory 'Tecnomatix'
. (Join-Path $PSScriptRoot '..\..\..\tools\envdetect.ps1')
. (Join-Path $PSScriptRoot 'txai-config.ps1')
$ClientRoot = Split-Path -Parent $PSScriptRoot
$TxRoot = Split-Path -Parent $ClientRoot
$TaskRoot = Join-Path $TxRoot 'Task'
$Contracts = Join-Path $ClientRoot 'deploy\TxAi\TxAi.Contracts.dll'
$CfgPath = Join-Path $env:LOCALAPPDATA 'TxAi\txai.config.json'

function Stop-With([int]$Code, [string]$Message) {
    Write-Host $Message
    exit $Code
}

function Assert-Environment([bool]$NeedPlugin) {
    $problems = @()
    $script:TxInstallDir = $null

    $dll = Find-TxInstalls | Select-Object -Last 1
    if ($dll) { $script:TxInstallDir = $dll.Dir.TrimEnd('\') + '\'; Write-Host "[OK] Process Simulate $($dll.Version): $script:TxInstallDir" }
    else { $problems += '[X] Process Simulate not found (Tecnomatix.Engineering.dll). Ask the user for the install folder.' }

    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) { $problems += '[X] .NET SDK is not installed.' }
    if (-not (Get-Net48Pack)) {
        $problems += '[X] .NET Framework 4.8 Developer Pack (targeting pack) is missing.'
    }

    New-Item -ItemType Directory -Path $TaskRoot -Force | Out-Null
    try {
        $configResult = Initialize-TxAiConfig -TaskRoot $TaskRoot -ConfigPath $CfgPath
        $script:PipeName = $configResult.PipeName
    }
    catch { $problems += "[X] AI Bridge config initialization failed: $($_.Exception.Message)" }

    if ($problems.Count -gt 0) { Stop-With 10 (($problems -join "`n") + "`nEnvironment not ready.") }

    $staged = Join-Path $ClientRoot 'deploy\TxAi\TxAi.Addin.dll'
    if (-not (Test-Path $Contracts -PathType Leaf) -or -not (Test-Path $staged -PathType Leaf)) {
        Write-Host '[..] Building AI Client (add-in or contracts DLL missing) ...'
        try {
            & (Join-Path $PSScriptRoot 'package.ps1') -TxInstallDir $script:TxInstallDir | Out-Host
        }
        catch { Stop-With 12 "[X] AI Client build failed: $($_.Exception.Message)" }
        if (-not (Test-Path $Contracts -PathType Leaf) -or -not (Test-Path $staged -PathType Leaf)) {
            Stop-With 12 '[X] AI Client build did not produce both TxAi.Addin.dll and TxAi.Contracts.dll.'
        }
    }
    Write-Host '[OK] AI Client add-in and contracts staged'

    if ($NeedPlugin -and $script:TxInstallDir) {
        $found = Get-ChildItem (Join-Path $script:TxInstallDir 'DotNetCommands') -Recurse -Filter 'TxAi.Addin.dll' -ErrorAction SilentlyContinue | Select-Object -First 1
        $installed = if ($found) { $found.FullName } else { Join-Path $script:TxInstallDir 'DotNetCommands\TxAi\TxAi.Addin.dll' }
        if (-not (Test-Path $installed)) {
            Write-Host '[OK] Local preparation complete: plugin compiled and user config initialized.'
            Write-Host '[!] Next steps: open PowerShell as administrator and run the following command (the agent never self-elevates):'
            $source = (Join-Path $ClientRoot 'deploy\TxAi').Replace("'", "''")
            $destination = (Join-Path $script:TxInstallDir 'DotNetCommands').Replace("'", "''")
            Write-Host "Copy-Item -LiteralPath '$source' -Destination '$destination' -Recurse -Force"
            $problems += '[X] AI Bridge add-in not installed. Complete the administrator copy above, then restart Process Simulate, open a Study, click AI > AI Bridge and rerun setup.'
        }
        elseif ((Test-Path $staged) -and ((Get-FileHash $installed).Hash -ne (Get-FileHash $staged).Hash)) {
            Write-Host '[!] Installed add-in differs from the latest build; suggest the user update it (admin) and restart Process Simulate.'
        }
        else { Write-Host '[OK] Add-in installed' }
    }

    if ($problems.Count -gt 0) { Stop-With 10 (($problems -join "`n") + "`nEnvironment not ready.") }
}

function Invoke-Bridge([string]$Method, $Params) {
    $pipe = New-Object System.IO.Pipes.NamedPipeClientStream('.', $script:PipeName, [System.IO.Pipes.PipeDirection]::InOut)
    try { $pipe.Connect(3000) } catch { $pipe.Dispose(); return $null }
    try {
        $enc = New-Object System.Text.UTF8Encoding($false)
        $writer = New-Object System.IO.StreamWriter($pipe, $enc)
        $writer.AutoFlush = $true
        $reader = New-Object System.IO.StreamReader($pipe, $enc)
        $request = @{ id = [guid]::NewGuid().ToString('N'); method = $Method; params = $Params } | ConvertTo-Json -Depth 10 -Compress
        $writer.WriteLine($request)
        $line = $reader.ReadLine()
        if ($line) { return ($line | ConvertFrom-Json) }
        return $null
    }
    finally { $pipe.Dispose() }
}

function Assert-Bridge {
    $pong = Invoke-Bridge 'ping' @{}
    if (-not $pong -or -not $pong.ok) {
        Stop-With 11 'AI Bridge is NOT running. Ask the user to open a Study in Process Simulate and click the "AI Bridge" command (category "AI"), then retry.'
    }
    Write-Host '[OK] AI Bridge is running'
}

function Assert-SkillName {
    if ($Skill -notmatch '^[A-Za-z][A-Za-z0-9_]*$') { Stop-With 2 'Skill must be a PascalCase identifier (letters, digits, underscore).' }
}

$ProjectTemplate = @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net48</TargetFramework>
    <LangVersion>5</LangVersion>
    <AssemblyName>$(MSBuildProjectName)</AssemblyName>
    <RootNamespace>TxAiSkills.$(MSBuildProjectName)</RootNamespace>
    <AppendTargetFrameworkToOutputPath>false</AppendTargetFrameworkToOutputPath>
    <OutputPath>.\</OutputPath>
    <DebugType>none</DebugType>
  </PropertyGroup>
  <ItemGroup>
    <Reference Include="TxAi.Contracts"><HintPath>$(TxContractsDll)</HintPath><Private>false</Private></Reference>
    <Reference Include="Tecnomatix.Engineering"><HintPath>$(TxInstallDir)Tecnomatix.Engineering.dll</HintPath><Private>false</Private></Reference>
    <!-- Add Tecnomatix.Engineering.Ui.dll here only when UI types are needed. -->
  </ItemGroup>
</Project>
'@

function Build-Skill {
    Assert-SkillName
    $dir = Join-Path $TaskRoot $Skill
    if (-not (Test-Path $dir)) { Stop-With 12 "Skill folder not found: $dir (create the .cs source there first)." }
    $proj = Join-Path $dir "$Skill.csproj"
    if (-not (Test-Path $proj)) { Set-Content $proj $ProjectTemplate -Encoding UTF8 }
    $out = Join-Path $dir "$Skill.dll"
    if (Test-Path $out) { Remove-Item $out -Force }
    # Doubled trailing backslash keeps Windows PowerShell 5.1 from escaping the closing quote.
    $installArg = $script:TxInstallDir.TrimEnd('\') + '\\'
    & dotnet build $proj -c Release "-p:TxInstallDir=$installArg" "-p:TxContractsDll=$Contracts" | Out-Host
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $out)) { Stop-With 12 "Build FAILED for $Skill. Fix the compiler errors above and rebuild." }
    Write-Host "[OK] Built $out"
    return $out
}

switch ($Command) {
    'setup' { Assert-Environment $true; Assert-Bridge; Write-Host 'Environment ready.' }
    'ping' { Assert-Environment $false; Assert-Bridge }
    'build' { Assert-Environment $false; [void](Build-Skill) }
    'run' {
        Assert-Environment $true
        Assert-SkillName
        $dll = Join-Path (Join-Path $TaskRoot $Skill) "$Skill.dll"
        if (-not (Test-Path $dll)) { Stop-With 12 "DLL not found: $dll. Run 'build $Skill' first." }
        Assert-Bridge
        $skillArgs = $ArgsJson | ConvertFrom-Json
        $response = Invoke-Bridge 'run_dll' @{ path = $dll; args = $skillArgs; timeoutMs = $TimeoutMs }
        if (-not $response) { Stop-With 13 'No response from AI Bridge.' }
        $response | ConvertTo-Json -Depth 20
        if (-not $response.ok) { exit 13 }
    }
}
exit 0
