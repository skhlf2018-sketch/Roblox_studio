# 로블록스 스튜디오 MCP 서버(%LOCALAPPDATA%\Roblox\mcp.bat)에 명령 하나를 보내고 결과를 출력하는 스크립트.
# 사용:
#   tools\studio-mcp.ps1 -Method tools/list
#   tools\studio-mcp.ps1 -Method tools/call -Tool execute_luau -ArgsJson '{"code":"print(1)"}'
#   tools\studio-mcp.ps1 -Method tools/call -Tool execute_luau -ArgsFile C:\path\args.json
# 스튜디오에서 "Enable Studio as MCP server"가 켜져 있어야 합니다.
param(
  [string]$Method = "tools/list",
  [string]$Tool = "",
  [string]$ArgsJson = "{}",
  [string]$ArgsFile = "",
  [int]$TimeoutMs = 60000,
  [switch]$Raw
)
$ErrorActionPreference = "Stop"
if ($ArgsFile) { $ArgsJson = Get-Content -Raw -Encoding UTF8 $ArgsFile }

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "cmd.exe"
$psi.Arguments = "/c `"$env:LOCALAPPDATA\Roblox\mcp.bat`""
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.UseShellExecute = $false
$psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
$p = [System.Diagnostics.Process]::Start($psi)
$utf8 = New-Object System.Text.UTF8Encoding($false)
$stdin = New-Object System.IO.StreamWriter($p.StandardInput.BaseStream, $utf8)
$stdin.AutoFlush = $true

function Send-Line([string]$line) { $stdin.Write($line + "`n") }
$script:pendingRead = $null
function Read-Line([int]$ms) {
  if ($null -eq $script:pendingRead) { $script:pendingRead = $p.StandardOutput.ReadLineAsync() }
  if ($script:pendingRead.Wait($ms)) {
    $r = $script:pendingRead.Result
    $script:pendingRead = $null
    return $r
  }
  return $null
}

Send-Line '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"claude-code-bridge","version":"0.1"}}}'
$initResp = Read-Line 15000
if (-not $initResp) { try { $p.Kill() } catch {}; throw "initialize 응답 없음 (스튜디오 MCP가 꺼져 있나요?)" }
Send-Line '{"jsonrpc":"2.0","method":"notifications/initialized"}'
# 스튜디오가 중계 서버에 붙을 시간을 줌 (tools/list 로 도구가 생길 때까지 대기)
$ready = $false
$waitDeadline = [DateTime]::UtcNow.AddMilliseconds(20000)
while (-not $ready -and [DateTime]::UtcNow -lt $waitDeadline) {
  Send-Line '{"jsonrpc":"2.0","id":100,"method":"tools/list","params":{}}'
  $l = $null
  $d2 = [DateTime]::UtcNow.AddMilliseconds(15000)
  while ([DateTime]::UtcNow -lt $d2) { $l = Read-Line 1000; if ($l -and $l -match '"id":\s*100\b') { break } }
  if ($l -and $l -match '"name"') { $ready = $true } else { Start-Sleep -Milliseconds 1000 }
}
# 스튜디오 인스턴스가 실제로 등록될 때까지 기다림 (list_roblox_studios 가 비어 있지 않을 때까지)
if ($Method -eq "tools/call" -and $Tool -ne "list_roblox_studios") {
  $sd = [DateTime]::UtcNow.AddMilliseconds(20000)
  $seq = 200
  while ([DateTime]::UtcNow -lt $sd) {
    Send-Line ('{"jsonrpc":"2.0","id":' + $seq + ',"method":"tools/call","params":{"name":"list_roblox_studios","arguments":{}}}')
    $l = $null
    $d3 = [DateTime]::UtcNow.AddMilliseconds(10000)
    while ([DateTime]::UtcNow -lt $d3) { $l = Read-Line 1000; if ($l -and $l -match ('"id":\s*' + $seq + '\b')) { break } }
    if ($l -and $l -match '\\"id\\"') { break }
    $seq++
    Start-Sleep -Milliseconds 1000
  }
}
Start-Sleep -Milliseconds 500

if ($Method -eq "tools/call") {
  $req = '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"' + $Tool + '","arguments":' + $ArgsJson + '}}'
} else {
  $req = '{"jsonrpc":"2.0","id":2,"method":"' + $Method + '","params":{}}'
}
Send-Line $req
$resp = $null
$deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
while ([DateTime]::UtcNow -lt $deadline) {
  $line = Read-Line 1000
  if ($null -eq $line) { if ($p.HasExited) { break } else { continue } }
  if ($Raw) { "RAW: " + $line }
  if ($line -match '"id":\s*2\b') { $resp = $line; break }
}
try { $p.Kill() } catch {}
if (-not $resp) { throw "응답 없음 ($Method $Tool)" }

# 결과 정리: tools/call 이면 content[].text 만 출력
try {
  $obj = $resp | ConvertFrom-Json
  if ($obj.error) { "ERROR: " + ($obj.error | ConvertTo-Json -Compress); exit 1 }
  if ($Method -eq "tools/call" -and $obj.result.content) {
    foreach ($c in $obj.result.content) { if ($c.type -eq "text") { $c.text } else { ($c | ConvertTo-Json -Compress) } }
    if ($obj.result.isError) { exit 1 }
  } elseif ($Method -eq "tools/list" -and $Tool) {
    # -Tool 에 쉼표로 여러 개: 그 도구들의 입력 스키마만 출력
    $want = $Tool.Split(",") | ForEach-Object { $_.Trim() }
    foreach ($t in $obj.result.tools) { if ($want -contains $t.name) { "== " + $t.name; ($t.inputSchema | ConvertTo-Json -Depth 10 -Compress) } }
  } elseif ($Method -eq "tools/list") {
    foreach ($t in $obj.result.tools) { "- " + $t.name + ": " + $t.description }
  } else {
    $obj.result | ConvertTo-Json -Depth 8
  }
} catch {
  $resp
}
