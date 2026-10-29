<#
tokencost.ps1 - ESTIMATE token usage and cost of the current Copilot chat turn and session.
tokencost.ps1 - Estimate (not exact) token usage and USD cost.

The assistant cannot see real usage counters. This script rebuilds an estimate from the Copilot
transcript (user text, assistant text, tool-call arguments). Tool RESULTS and hidden reasoning are
not logged, so they are approximated with -ToolResult / -Base. Always label the result "estimate".

Usage (absolute path required):
  powershell -NoProfile -ExecutionPolicy Bypass -File <abs>\tools\tokencost.ps1 -Model claude-sonnet-5.5
Params:
  -Model       model id in Copilot models.json (default claude-sonnet-5.5)
  -Compare     extra model ids to price side by side (default: a small reference set)
  -Session     explicit transcript .jsonl (default: newest transcript of any workspace)
  -Base        tokens of system prompt + tool schemas + attachments sent on every call (default 25000)
  -ToolResult  average tokens of tool output per tool call (default 800)
  -MaxContext  context size at which auto-summarisation is assumed to reset it (default 150000)
  -TranscriptDir  folder searched recursively for the newest *.jsonl transcript (default env MFG_TRANSCRIPT_DIR,
                  else the VS Code Copilot Chat storage)
  -InChars/-OutChars/-Calls  manual mode for clients without a Copilot transcript (Codex, Claude, ...): characters
                  of the turn read by / written by the assistant and the number of model calls; session total is n/a
  -Refresh     re-read prices from models.json next to the transcript and update tools\model_prices.json
Price unit in models.json: USD cents per 1,000,000 tokens (batch_size 1000000).
#>
param(
    [string]$Model = 'claude-sonnet-5.5',
    [string[]]$Compare = @('claude-haiku-5.5','claude-sonnet-5.5','claude-opus-5.5','gpt-6-sol','gemini-3.8-flash'),
    [string]$Session = '',
    [int]$Base = 25000,
    [int]$ToolResult = 800,
    [int]$MaxContext = 150000,
    [string]$TranscriptDir = $env:MFG_TRANSCRIPT_DIR,
    [int]$InChars = 0,
    [int]$OutChars = 0,
    [int]$Calls = 1,
    [switch]$Refresh
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$snap = Join-Path $here 'model_prices.json'

# ---- locate transcript ----
$manual = $false
if (-not $Session) {
    if ($TranscriptDir) {
        $cand = Get-ChildItem -Path $TranscriptDir -Recurse -Filter *.jsonl -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
    } else {
        $root = Join-Path $env:APPDATA 'Code\User\workspaceStorage'
        $cand = Get-ChildItem -Path $root -Recurse -Filter *.jsonl -ErrorAction SilentlyContinue |
            Where-Object { $_.DirectoryName -like '*GitHub.copilot-chat\transcripts' } |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
    }
    if ($cand) { $Session = $cand.FullName }
}
if (-not $Session) {
    if ($InChars -gt 0 -or $OutChars -gt 0) { $manual = $true }
    else {
        Write-Host 'ERROR: no transcript found. Pass -Session / -TranscriptDir, or use manual mode: -InChars <n> -OutChars <n> [-Calls <n>].'
        exit 20
    }
}
$sid = 'manual'
if (-not $manual) { $sid = [IO.Path]::GetFileNameWithoutExtension($Session) }

# ---- prices: refresh snapshot from models.json when available ----
$mj = $null
if (-not $manual) {
    $dbg = Join-Path (Split-Path -Parent (Split-Path -Parent $Session)) ('debug-logs\' + $sid + '\models.json')
    if (Test-Path $dbg) { $mj = $dbg }
}
if ($mj -and ($Refresh -or -not (Test-Path $snap))) {
    $raw = [IO.File]::ReadAllText($mj, [Text.Encoding]::UTF8) | ConvertFrom-Json
    $rows = @()
    foreach ($m in $raw) {
        $tp = $m.billing.token_prices.default
        if ($tp -and $tp.input_price -gt 0) {
            $rows += [pscustomobject]@{ id = $m.id; name = $m.name; input = [double]$tp.input_price; output = [double]$tp.output_price; cache_read = [double]$tp.cache_read_price }
        }
    }
    $rows | ConvertTo-Json | Set-Content -Path $snap -Encoding UTF8
}
if (-not (Test-Path $snap)) { Write-Host 'ERROR: no price snapshot (tools\model_prices.json); run once inside a Copilot session with -Refresh'; exit 21 }
$prices = [IO.File]::ReadAllText($snap, [Text.Encoding]::UTF8) | ConvertFrom-Json
function Get-Price([string]$id) { $prices | Where-Object { $_.id -eq $id } | Select-Object -First 1 }

# ---- token estimator: ~4 chars/token for Latin, ~1.5 chars/token for CJK ----
function Est([string]$s) {
    if (-not $s) { return 0 }
    $cjk = [regex]::Matches($s, '[\u3000-\u9fff\uff00-\uffef]').Count
    return [int][math]::Ceiling(($s.Length - $cjk) / 4.0 + $cjk / 1.5)
}

# ---- replay transcript ----
$ctx = $Base; $lastBilled = 0
$sess = @{ calls = 0; fresh = 0; cached = 0; out = 0 }
$turn = @{ calls = 0; fresh = 0; cached = 0; out = 0 }
if ($manual) {
    $n = [math]::Max($Calls, 1)
    $inTok = [int][math]::Ceiling($InChars / 4.0)
    $turn = @{ calls = $n; fresh = $Base + $inTok; cached = ($n - 1) * ($Base + $inTok); out = [int][math]::Ceiling($OutChars / 4.0) }
    $lines = @()
} else {
    $lines = [IO.File]::ReadAllLines($Session, [Text.Encoding]::UTF8)
}
foreach ($l in $lines) {
    if (-not $l) { continue }
    $o = $l | ConvertFrom-Json
    switch ($o.type) {
        'user.message' {
            $ctx += Est ([string]$o.data.content)
            $turn = @{ calls = 0; fresh = 0; cached = 0; out = 0 }
        }
        'assistant.message' {
            $cached = [math]::Min($ctx, $lastBilled)
            $fresh = $ctx - $cached
            $out = Est ([string]$o.data.content)
            $n = 0
            foreach ($t in @($o.data.toolRequests)) { if ($t) { $out += Est ([string]$t.arguments); $n++ } }
            foreach ($b in @($sess, $turn)) { $b.calls++; $b.fresh += $fresh; $b.cached += $cached; $b.out += $out }
            $ctx += $out
            $lastBilled = $ctx
            $ctx += $n * $ToolResult
            if ($ctx -gt $MaxContext) { $ctx = $Base + 8000; $lastBilled = 0 }   # assume auto-summarisation resets context
        }
    }
}

function Cost($b, $p) {
    [math]::Round((($b.fresh * $p.input) + ($b.cached * $p.cache_read) + ($b.out * $p.output)) / 1e6 / 100, 4)
}

Write-Host "Token and cost ESTIMATE (not exact values)"
Write-Host ("transcript : " + $sid)
Write-Host ("assumptions: base={0} tok/call, tool result={1} tok/call, hidden reasoning not counted" -f $Base, $ToolResult)
Write-Host ""
$pairs = @(@('This turn   ', $turn), @('Session total', $sess))
if ($manual) { $pairs = @(@('This turn   ', $turn)); Write-Host 'mode       : manual (no transcript); session total n/a; Latin text assumed, CJK is under-counted' }
foreach ($pair in $pairs) {
    $b = $pair[1]
    Write-Host ("{0}: calls={1} input_fresh={2} input_cached={3} output={4} total={5}" -f $pair[0], $b.calls, $b.fresh, $b.cached, $b.out, ($b.fresh + $b.cached + $b.out))
}
Write-Host ""
$ids = @($Model) + @($Compare | Where-Object { $_ -ne $Model })
Write-Host ("{0,-22} {1,10} {2,10} {3,12} {4,12}" -f 'Model', 'in $/1M', 'out $/1M', 'turn USD', 'session USD')
foreach ($id in $ids) {
    $p = Get-Price $id
    if (-not $p) { Write-Host ("{0,-22} (no price)" -f $id); continue }
    $mark = ''; if ($id -eq $Model) { $mark = ' *' }
    $sc = 'n/a'; if (-not $manual) { $sc = ('{0:N4}' -f (Cost $sess $p)) }
    Write-Host ("{0,-22} {1,10:N2} {2,10:N2} {3,12:N4} {4,12}{5}" -f $id, ($p.input / 100), ($p.output / 100), (Cost $turn $p), $sc, $mark)
}
Write-Host "(* = model used; prices from Copilot models.json, cached input billed at cache_read price)"
exit 0
